use std::{collections::HashMap, net::TcpListener, path::PathBuf, time::Duration};

use contract::{v1, KshiftServiceClient};
use kshift_server::{
    auth::TokenAuthenticator,
    config::{ApiLimits, ApiTimeouts, DatabaseConfig, ServerConfig},
    notifications::NotificationHub,
    server,
};
use tokio_util::sync::CancellationToken;
use tonic::Request;
use uuid::Uuid;

mod common;

use common::TestApi;

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn grpc_health_and_graceful_shutdown_work() {
    let Some(db) = common::TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    let token = "transport-test-token".to_owned();
    let test_api = TestApi::create(db.pool.clone(), HashMap::from([(admin_id, token.clone())]));
    let authenticator =
        TokenAuthenticator::from_entries([(token.clone(), admin_id)]).expect("auth should build");

    let port = TcpListener::bind("127.0.0.1:0")
        .expect("ephemeral listener should bind")
        .local_addr()
        .expect("listener address should exist")
        .port();
    let address = format!("127.0.0.1:{port}");
    let config = ServerConfig {
        bind_address: address.clone(),
        database: DatabaseConfig {
            url: "postgres://redacted@127.0.0.1/unused".to_owned(),
            min_connections: 1,
            max_connections: 4,
            acquire_timeout: Duration::from_secs(5),
            statement_timeout: Duration::from_secs(15),
            lock_timeout: Duration::from_secs(5),
            idle_in_transaction_timeout: Duration::from_secs(30),
        },
        auth_file: PathBuf::from("/unused"),
        tls: None,
        allow_insecure: true,
        limits: ApiLimits {
            unary_rpc: 100,
            write_transactions: 8,
            event_streams: 32,
            streams_per_user: 1,
        },
        timeouts: ApiTimeouts {
            unary_request: Duration::from_secs(15),
            write_transaction: Duration::from_secs(10),
        },
        heartbeat_interval: Duration::from_secs(15),
        event_batch_size: 128,
        event_channel_capacity: 64,
        notification_channel_capacity: 256,
        retention_days: 7,
        log_filter: "kshift_server=info".to_owned(),
    };
    let shutdown = CancellationToken::new();
    let server_task = tokio::spawn(server::serve(
        config,
        db.pool.clone(),
        authenticator,
        NotificationHub::new(256),
        shutdown.clone(),
    ));

    let endpoint = format!("http://{address}");
    let mut health = connect_health(&endpoint).await;
    let health_response = health
        .check(tonic_health::pb::HealthCheckRequest {
            service: String::new(),
        })
        .await
        .expect("health check should succeed")
        .into_inner();
    assert_eq!(
        health_response.status,
        tonic_health::pb::health_check_response::ServingStatus::Serving as i32
    );

    let mut client = connect_service(&endpoint).await;
    let mut list_request = Request::new(v1::ListProjectsRequest {});
    list_request
        .metadata_mut()
        .insert("authorization", format!("Bearer {token}").parse().unwrap());
    let projects = client
        .list_projects(list_request)
        .await
        .expect("authenticated ListProjects should succeed")
        .into_inner();
    assert!(projects.projects.is_empty());

    shutdown.cancel();
    tokio::time::timeout(Duration::from_secs(5), server_task)
        .await
        .expect("server should shut down")
        .expect("server task should join")
        .expect("server should exit cleanly");
    drop(test_api);
    db.cleanup().await;
}

async fn connect_health(
    endpoint: &str,
) -> tonic_health::pb::health_client::HealthClient<tonic::transport::Channel> {
    let mut last_error = None;
    for _ in 0..50 {
        match tonic::transport::Endpoint::from_shared(endpoint.to_owned())
            .expect("health endpoint should parse")
            .connect()
            .await
        {
            Ok(channel) => return tonic_health::pb::health_client::HealthClient::new(channel),
            Err(error) => {
                last_error = Some(error);
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        }
    }
    panic!("health client did not connect: {last_error:?}");
}

async fn connect_service(endpoint: &str) -> KshiftServiceClient<tonic::transport::Channel> {
    let mut last_error = None;
    for _ in 0..50 {
        match KshiftServiceClient::connect(endpoint.to_owned()).await {
            Ok(client) => return client,
            Err(error) => {
                last_error = Some(error);
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        }
    }
    panic!("Kshift client did not connect: {last_error:?}");
}
