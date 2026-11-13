use std::time::Duration;

use sqlx::PgPool;
use tokio_util::sync::CancellationToken;

pub fn spawn(pool: PgPool, shutdown: CancellationToken) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(60 * 60));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            tokio::select! {
                _ = shutdown.cancelled() => return,
                _ = interval.tick() => {
                    match cleanup(&pool).await {
                        Ok((events, commands)) if events > 0 || commands > 0 => {
                            tracing::info!(
                                expired_events = events,
                                expired_commands = commands,
                                "expired synchronization history removed"
                            );
                        }
                        Ok(_) => {}
                        Err(error) => {
                            tracing::warn!(error = %error, "retention cleanup failed");
                        }
                    }
                }
            }
        }
    })
}

async fn cleanup(pool: &PgPool) -> anyhow::Result<(u64, u64)> {
    let mut tx = pool.begin().await?;
    let events = sqlx::query("DELETE FROM kshift.change_event WHERE expires_at <= now()")
        .execute(&mut *tx)
        .await?
        .rows_affected();
    let commands = sqlx::query("DELETE FROM kshift.command_result WHERE expires_at <= now()")
        .execute(&mut *tx)
        .await?
        .rows_affected();
    tx.commit().await?;
    Ok((events, commands))
}
