use std::{fs, str::FromStr, time::Duration};

use anyhow::{bail, Context};
use contract::{
    v1::kshift_service_server::KshiftServiceServer, MAX_UNARY_REQUEST_BYTES,
    MAX_UNARY_RESPONSE_BYTES,
};
use sqlx::PgPool;
use tokio_util::sync::CancellationToken;
use tonic::transport::{Identity, Server, ServerTlsConfig};
use tonic_health::{server::health_reporter, ServingStatus};
use tower::limit::ConcurrencyLimitLayer;
use tower_http::trace::{DefaultMakeSpan, TraceLayer};
use tracing::Level;

use crate::{
    auth::TokenAuthenticator,
    config::ServerConfig,
    db,
    notifications::NotificationHub,
    service::{ApiSettings, KshiftApi},
};

pub const SERVICE_NAME: &str = "kshift.v1.KshiftService";

pub async fn serve(
    config: ServerConfig,
    pool: PgPool,
    auth: TokenAuthenticator,
    notifications: NotificationHub,
    shutdown: CancellationToken,
) -> anyhow::Result<()> {
    let (health_reporter, health_service) = health_reporter();
    health_reporter
        .set_service_status("", ServingStatus::NotServing)
        .await;
    health_reporter
        .set_service_status(SERVICE_NAME, ServingStatus::NotServing)
        .await;

    let probe_reporter = health_reporter.clone();
    let probe_pool = pool.clone();
    let probe_shutdown = shutdown.clone();
    let probe_task = tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            tokio::select! {
                _ = probe_shutdown.cancelled() => return,
                _ = interval.tick() => {
                    let status = if db::ping(&probe_pool, Duration::from_secs(2)).await {
                        ServingStatus::Serving
                    } else {
                        ServingStatus::NotServing
                    };
                    probe_reporter.set_service_status("", status).await;
                    probe_reporter.set_service_status(SERVICE_NAME, status).await;
                }
            }
        }
    });

    health_reporter
        .set_service_status("", ServingStatus::Serving)
        .await;
    health_reporter
        .set_service_status(SERVICE_NAME, ServingStatus::Serving)
        .await;

    let settings = ApiSettings {
        limits: config.limits.clone(),
        timeouts: config.timeouts.clone(),
        heartbeat_interval: config.heartbeat_interval,
        event_batch_size: config.event_batch_size,
        event_channel_capacity: config.event_channel_capacity,
        retention_days: config.retention_days,
    };
    let api = KshiftApi::new(pool, auth, notifications, settings, shutdown.clone());
    let service = KshiftServiceServer::new(api)
        .max_decoding_message_size(MAX_UNARY_REQUEST_BYTES)
        .max_encoding_message_size(MAX_UNARY_RESPONSE_BYTES);

    let mut builder = Server::builder();
    if let Some(tls) = &config.tls {
        let cert = fs::read(&tls.certificate_path).with_context(|| {
            format!(
                "failed to read TLS certificate {}",
                tls.certificate_path.display()
            )
        })?;
        let key = fs::read(&tls.private_key_path).with_context(|| {
            format!(
                "failed to read TLS private key {}",
                tls.private_key_path.display()
            )
        })?;
        builder = builder
            .tls_config(ServerTlsConfig::new().identity(Identity::from_pem(cert, key)))
            .context("failed to configure TLS")?;
    } else if !config.allow_insecure {
        bail!("TLS is required for Kshift server");
    }

    let shutdown_for_serve = shutdown.clone();
    let router = builder
        .layer(ConcurrencyLimitLayer::new(config.limits.unary_rpc))
        .layer(TraceLayer::new_for_grpc().make_span_with(DefaultMakeSpan::new().level(Level::INFO)))
        .add_service(health_service)
        .add_service(service);

    let address = std::net::SocketAddr::from_str(&config.bind_address)
        .context("KSHIFT_BIND_ADDR must be an IP address and port")?;
    tracing::info!(
        bind_address = %address,
        tls = config.tls.is_some(),
        schema_version = domain::SCHEMA_VERSION,
        "Kshift server is listening"
    );

    router
        .serve_with_shutdown(address, async move {
            shutdown_for_serve.cancelled().await;
        })
        .await
        .map_err(|error| anyhow::anyhow!("gRPC server stopped unexpectedly: {error}"))?;

    shutdown.cancel();
    let _ = probe_task.await;
    Ok(())
}
