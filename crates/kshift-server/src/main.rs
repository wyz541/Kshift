use std::io::{self, Read};

use anyhow::{bail, Context};
use kshift_server::{
    auth::{hash_token, TokenAuthenticator},
    config::DatabaseConfig,
    db, migration,
    notifications::NotificationHub,
    retention, server, telemetry,
};
use serde_json::json;
use tokio_util::sync::CancellationToken;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let command = std::env::args().nth(1).unwrap_or_else(|| "help".to_owned());
    match command.as_str() {
        "serve" => serve().await,
        "migrate" => migrate().await,
        "check" => check().await,
        "hash-token" => hash_token_command(),
        "bootstrap-user" => bootstrap_user().await,
        "help" | "--help" | "-h" => {
            print_help();
            Ok(())
        }
        other => bail!("unknown command {other}; run kshift-server --help"),
    }
}

async fn serve() -> anyhow::Result<()> {
    let config = kshift_server::config::ServerConfig::from_env()?;
    telemetry::init(&config.log_filter)?;
    let pool = db::connect(&config.database).await?;
    let evidence = migration::verify(&pool).await?;
    tracing::info!(
        schema_version = evidence.schema_version,
        migration_digest = %evidence.migration_digest,
        migration_count = evidence.migration_count,
        postgres_version = %evidence.postgres_version,
        "database migration check passed"
    );

    let auth = TokenAuthenticator::from_path(&config.auth_file)?;
    let notifications = NotificationHub::new(config.notification_channel_capacity);
    let shutdown = CancellationToken::new();
    let listener_task = kshift_server::notifications::spawn_listener(
        pool.clone(),
        notifications.clone(),
        shutdown.clone(),
    );
    let retention_task = retention::spawn(pool.clone(), shutdown.clone());
    let signal_task = tokio::spawn(shutdown_signal(shutdown.clone()));

    let server_result =
        server::serve(config, pool.clone(), auth, notifications, shutdown.clone()).await;
    shutdown.cancel();
    let _ = signal_task.await;
    let _ = listener_task.await;
    let _ = retention_task.await;
    pool.close().await;
    server_result
}

async fn migrate() -> anyhow::Result<()> {
    let config = DatabaseConfig::from_env()?;
    let pool = db::connect(&config).await?;
    let evidence = migration::run(&pool).await?;
    println!("{}", serde_json::to_string_pretty(&evidence)?);
    pool.close().await;
    Ok(())
}

async fn check() -> anyhow::Result<()> {
    let config = DatabaseConfig::from_env()?;
    let pool = db::connect(&config).await?;
    let evidence = migration::verify(&pool).await?;
    let healthy = db::ping(&pool, config.acquire_timeout).await;
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "healthy": healthy,
            "schema_version": evidence.schema_version,
            "migration_digest": evidence.migration_digest,
            "migration_count": evidence.migration_count,
            "postgres_version": evidence.postgres_version,
            "postgres_version_num": evidence.postgres_version_num
        }))?
    );
    pool.close().await;
    if !healthy {
        bail!("database health check failed");
    }
    Ok(())
}

#[derive(serde::Deserialize)]
struct BootstrapUser {
    id: uuid::Uuid,
    display_name: String,
    #[serde(default)]
    is_admin: bool,
}

async fn bootstrap_user() -> anyhow::Result<()> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .context("failed to read bootstrap user from stdin")?;
    let user: BootstrapUser =
        serde_json::from_str(&input).context("bootstrap user must be valid JSON")?;
    let display_name = user.display_name.trim();
    if display_name.is_empty() || display_name.chars().count() > 120 {
        bail!("display_name must contain 1 to 120 characters");
    }

    let config = DatabaseConfig::from_env()?;
    let pool = db::connect(&config).await?;
    migration::verify(&pool).await?;
    sqlx::query(
        r#"
        INSERT INTO kshift.app_user (id, display_name, is_admin, is_active)
        VALUES ($1, $2, $3, true)
        "#,
    )
    .bind(user.id)
    .bind(display_name)
    .bind(user.is_admin)
    .execute(&pool)
    .await
    .context("failed to insert user; the UUID may already exist")?;
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "id": user.id,
            "display_name": display_name,
            "is_admin": user.is_admin,
            "is_active": true
        }))?
    );
    pool.close().await;
    Ok(())
}

fn hash_token_command() -> anyhow::Result<()> {
    let mut token = String::new();
    io::stdin()
        .read_to_string(&mut token)
        .context("failed to read token from stdin")?;
    while token.ends_with('\n') || token.ends_with('\r') {
        token.pop();
    }
    if token.is_empty() {
        bail!("token from stdin must not be empty");
    }
    println!("{}", hex::encode(hash_token(&token)));
    Ok(())
}

async fn shutdown_signal(shutdown: CancellationToken) {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut terminate = match signal(SignalKind::terminate()) {
            Ok(value) => value,
            Err(error) => {
                tracing::error!(error = %error, "failed to install SIGTERM handler");
                shutdown.cancelled().await;
                return;
            }
        };
        tokio::select! {
            result = tokio::signal::ctrl_c() => {
                if let Err(error) = result {
                    tracing::error!(error = %error, "failed to listen for SIGINT");
                }
            }
            _ = terminate.recv() => {}
        }
    }

    #[cfg(not(unix))]
    {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::error!(error = %error, "failed to listen for Ctrl+C");
        }
    }

    tracing::info!("shutdown signal received");
    shutdown.cancel();
}

fn print_help() {
    println!(
        "Kshift server\n\nCommands:\n  serve       Verify schema and serve gRPC over TLS\n  migrate     Apply migrations and record the migration digest\n  check       Verify PostgreSQL 18, migrations and database health\n  hash-token  Read a token from stdin and print its SHA-256\n  bootstrap-user  Insert one user from a JSON object on stdin\n"
    );
}
