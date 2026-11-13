use std::time::Duration;

use sqlx::{postgres::PgListener, PgPool};
use tokio::sync::broadcast;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

pub const NOTIFICATION_CHANNEL: &str = "kshift_changes";

#[derive(Clone)]
pub struct NotificationHub {
    sender: broadcast::Sender<Uuid>,
}

impl NotificationHub {
    pub fn new(capacity: usize) -> Self {
        let (sender, _receiver) = broadcast::channel(capacity);
        Self { sender }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Uuid> {
        self.sender.subscribe()
    }

    pub fn publisher(&self) -> broadcast::Sender<Uuid> {
        self.sender.clone()
    }
}

pub fn spawn_listener(
    pool: PgPool,
    hub: NotificationHub,
    shutdown: CancellationToken,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            if shutdown.is_cancelled() {
                return;
            }
            match PgListener::connect_with(&pool).await {
                Ok(mut listener) => {
                    if let Err(error) = listener.listen(NOTIFICATION_CHANNEL).await {
                        tracing::warn!(error = %error, "failed to subscribe to PostgreSQL notifications");
                        if wait_for_retry(&shutdown).await {
                            return;
                        }
                        continue;
                    }

                    tracing::info!(
                        channel = NOTIFICATION_CHANNEL,
                        "PostgreSQL notification listener is ready"
                    );
                    loop {
                        tokio::select! {
                            _ = shutdown.cancelled() => return,
                            result = listener.recv() => {
                                match result {
                                    Ok(notification) => {
                                        match Uuid::parse_str(notification.payload()) {
                                            Ok(project_id) => {
                                                let _ = hub.sender.send(project_id);
                                            }
                                            Err(_) => {
                                                tracing::warn!(
                                                    "received malformed Kshift notification payload"
                                                );
                                            }
                                        }
                                    }
                                    Err(error) => {
                                        tracing::warn!(error = %error, "PostgreSQL notification listener failed");
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
                Err(error) => {
                    tracing::warn!(error = %error, "failed to connect PostgreSQL notification listener");
                }
            }

            if wait_for_retry(&shutdown).await {
                return;
            }
        }
    })
}

async fn wait_for_retry(shutdown: &CancellationToken) -> bool {
    tokio::select! {
        _ = shutdown.cancelled() => true,
        _ = tokio::time::sleep(Duration::from_secs(1)) => false,
    }
}
