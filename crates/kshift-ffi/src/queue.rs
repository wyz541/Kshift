use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::Duration;

use tokio::sync::Notify;

struct QueueState {
    events: VecDeque<Vec<u8>>,
    bytes: usize,
    closed: bool,
}

pub struct ByteQueue {
    state: Mutex<QueueState>,
    notify: Notify,
    max_events: usize,
    max_bytes: usize,
}

impl ByteQueue {
    pub fn new(max_events: usize, max_bytes: usize) -> Self {
        Self {
            state: Mutex::new(QueueState {
                events: VecDeque::new(),
                bytes: 0,
                closed: false,
            }),
            notify: Notify::new(),
            max_events: max_events.max(1),
            max_bytes: max_bytes.max(1),
        }
    }

    pub async fn push(&self, bytes: Vec<u8>) -> bool {
        if bytes.len() > self.max_bytes {
            self.close();
            return false;
        }
        loop {
            let notified = self.notify.notified();
            {
                let mut state = self.lock();
                if state.closed {
                    return false;
                }
                if state.events.len() < self.max_events
                    && state.bytes.saturating_add(bytes.len()) <= self.max_bytes
                {
                    state.bytes = state.bytes.saturating_add(bytes.len());
                    state.events.push_back(bytes);
                    self.notify.notify_one();
                    return true;
                }
            }
            notified.await;
        }
    }

    pub async fn pop(&self, timeout: Option<Duration>) -> Result<Option<Vec<u8>>, ()> {
        let wait = async {
            loop {
                let notified = self.notify.notified();
                {
                    let mut state = self.lock();
                    if let Some(bytes) = state.events.pop_front() {
                        state.bytes = state.bytes.saturating_sub(bytes.len());
                        self.notify.notify_one();
                        return Ok(bytes);
                    }
                    if state.closed {
                        return Err(());
                    }
                }
                notified.await;
            }
        };
        match timeout {
            Some(duration) if duration.is_zero() => {
                let mut state = self.lock();
                if let Some(bytes) = state.events.pop_front() {
                    state.bytes = state.bytes.saturating_sub(bytes.len());
                    self.notify.notify_one();
                    Ok(Some(bytes))
                } else if state.closed {
                    Err(())
                } else {
                    Ok(None)
                }
            }
            Some(duration) => match tokio::time::timeout(duration, wait).await {
                Ok(Ok(bytes)) => Ok(Some(bytes)),
                Ok(Err(())) => Err(()),
                Err(_) => Ok(None),
            },
            None => wait.await.map(Some),
        }
    }

    pub fn close(&self) {
        let mut state = self.lock();
        state.closed = true;
        self.notify.notify_waiters();
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, QueueState> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}
