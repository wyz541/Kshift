use std::future::Future;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use tokio_util::sync::CancellationToken;

use crate::{ClientError, RetryPolicy};

static JITTER_SEQUENCE: AtomicU64 = AtomicU64::new(0x9e37_79b9_7f4a_7c15);

/// Compute bounded exponential backoff with deterministic jitter.
pub fn jittered_retry_delay(policy: RetryPolicy, attempt: u32) -> Duration {
    let exponent = attempt.saturating_sub(1).min(16);
    let base = policy
        .initial_delay
        .saturating_mul(1_u32 << exponent)
        .min(policy.max_delay);
    let random = next_jitter();
    let scale = 0.5 + (random as f64 / u64::MAX as f64) * 0.5;
    base.mul_f64(scale).min(policy.max_delay)
}

pub(crate) async fn retry_with_deadline<T, F, Fut>(
    policy: RetryPolicy,
    deadline_at: Instant,
    cancel: &CancellationToken,
    mut operation: F,
) -> Result<T, ClientError>
where
    F: FnMut(Duration) -> Fut,
    Fut: Future<Output = Result<T, ClientError>>,
{
    let mut attempt = 1_u32;
    loop {
        if cancel.is_cancelled() {
            return Err(ClientError::Cancelled);
        }
        let remaining = remaining(deadline_at)?;
        let result = tokio::select! {
            _ = cancel.cancelled() => return Err(ClientError::Cancelled),
            result = tokio::time::timeout(remaining, operation(remaining)) => {
                match result {
                    Ok(result) => result,
                    Err(_) => Err(ClientError::DeadlineExceeded),
                }
            },
        };
        match result {
            Ok(value) => return Ok(value),
            Err(error) if error.retryable() && attempt < policy.max_attempts => {
                let delay = jittered_retry_delay(policy, attempt);
                let now = Instant::now();
                let next = now
                    .checked_add(delay)
                    .ok_or(ClientError::DeadlineExceeded)?;
                if next >= deadline_at {
                    return Err(ClientError::DeadlineExceeded);
                }
                tokio::select! {
                    _ = cancel.cancelled() => return Err(ClientError::Cancelled),
                    _ = tokio::time::sleep_until(tokio::time::Instant::from_std(next)) => {}
                }
                attempt = attempt.saturating_add(1);
            }
            Err(error) => return Err(error),
        }
    }
}

fn remaining(deadline_at: Instant) -> Result<Duration, ClientError> {
    let remaining = deadline_at.saturating_duration_since(Instant::now());
    if remaining.is_zero() {
        Err(ClientError::DeadlineExceeded)
    } else {
        Ok(remaining)
    }
}

fn next_jitter() -> u64 {
    let mut value = JITTER_SEQUENCE.load(Ordering::Relaxed);
    value ^= value << 13;
    value ^= value >> 7;
    value ^= value << 17;
    JITTER_SEQUENCE.store(value, Ordering::Relaxed);
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_is_bounded_and_jittered() {
        let policy = RetryPolicy {
            max_attempts: 5,
            initial_delay: Duration::from_millis(100),
            max_delay: Duration::from_secs(1),
        };
        let first = jittered_retry_delay(policy, 1);
        let later = jittered_retry_delay(policy, 20);
        assert!(first >= Duration::from_millis(50));
        assert!(first <= Duration::from_millis(100));
        assert!(later >= Duration::from_millis(500));
        assert!(later <= Duration::from_secs(1));
    }
}
