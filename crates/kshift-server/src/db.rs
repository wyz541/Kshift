use std::{str::FromStr, time::Duration};

use anyhow::Context;
use sqlx::{
    postgres::{PgConnectOptions, PgPoolOptions},
    PgPool,
};

use crate::config::DatabaseConfig;

#[derive(Clone, Debug, serde::Serialize)]
pub struct DatabaseInfo {
    pub server_version: String,
    pub server_version_num: i32,
}

pub async fn connect(config: &DatabaseConfig) -> anyhow::Result<PgPool> {
    let connect_options = PgConnectOptions::from_str(&config.url)
        .context("KSHIFT_DATABASE_URL is not a valid PostgreSQL URL")?
        .application_name("kshift-server");
    let statement_timeout = duration_millis(config.statement_timeout);
    let lock_timeout = duration_millis(config.lock_timeout);
    let idle_timeout = duration_millis(config.idle_in_transaction_timeout);

    PgPoolOptions::new()
        .min_connections(config.min_connections)
        .max_connections(config.max_connections)
        .acquire_timeout(config.acquire_timeout)
        .after_connect(move |connection, _metadata| {
            let statement_timeout = statement_timeout.clone();
            let lock_timeout = lock_timeout.clone();
            let idle_timeout = idle_timeout.clone();
            Box::pin(async move {
                sqlx::query("SELECT set_config('statement_timeout', $1, false)")
                    .bind(&statement_timeout)
                    .execute(&mut *connection)
                    .await?;
                sqlx::query("SELECT set_config('lock_timeout', $1, false)")
                    .bind(&lock_timeout)
                    .execute(&mut *connection)
                    .await?;
                sqlx::query("SELECT set_config('idle_in_transaction_session_timeout', $1, false)")
                    .bind(&idle_timeout)
                    .execute(&mut *connection)
                    .await?;
                sqlx::query("SET TIME ZONE 'UTC'")
                    .execute(&mut *connection)
                    .await?;
                Ok(())
            })
        })
        .connect_with(connect_options)
        .await
        .context("failed to connect to PostgreSQL")
}

pub async fn inspect(pool: &PgPool) -> anyhow::Result<DatabaseInfo> {
    let (server_version, server_version_num): (String, i32) = sqlx::query_as(
        "SELECT current_setting('server_version'), current_setting('server_version_num')::int",
    )
    .fetch_one(pool)
    .await
    .context("failed to read PostgreSQL version")?;

    Ok(DatabaseInfo {
        server_version,
        server_version_num,
    })
}

pub async fn require_postgres_18(pool: &PgPool) -> anyhow::Result<DatabaseInfo> {
    let info = inspect(pool).await?;
    let major = info.server_version_num / 10_000;
    if major != 18 {
        anyhow::bail!(
            "Kshift requires PostgreSQL 18, but the server reports {} ({})",
            info.server_version,
            info.server_version_num
        );
    }
    Ok(info)
}

pub async fn ping(pool: &PgPool, timeout: Duration) -> bool {
    matches!(
        tokio::time::timeout(
            timeout,
            sqlx::query_scalar::<_, i32>("SELECT 1").fetch_one(pool)
        )
        .await,
        Ok(Ok(1))
    )
}

fn duration_millis(value: Duration) -> String {
    format!("{}ms", value.as_millis().max(1))
}
