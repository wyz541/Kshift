use std::{
    env, fs,
    path::{Path, PathBuf},
    time::Duration,
};

use chrono::NaiveDate;
use contract::{v1, KshiftServiceClient};
use domain::{Command, CommandEnvelope, TaskPriority, TaskStatus};
use kshift_client::{AuthToken, ClientConfig, KshiftClient, MAX_RESPONSE_BYTES};
use serde_json::json;
use tokio_util::sync::CancellationToken;
use tonic::transport::{Certificate, Channel, ClientTlsConfig, Endpoint};
use tonic::Request;
use tonic_health::pb::{
    health_check_response::ServingStatus, health_client::HealthClient, HealthCheckRequest,
};
use uuid::Uuid;

const SERVICE_NAME: &str = "kshift.v1.KshiftService";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mode = env::args().nth(1).unwrap_or_else(|| "health".to_owned());
    let endpoint = required_env("KSHIFT_ENDPOINT")?;
    let ca_path = PathBuf::from(required_env("KSHIFT_CA_PATH")?);
    let tls_domain = required_env("KSHIFT_TLS_DOMAIN")?;
    let output_path = env::var_os("KSHIFT_PROBE_OUTPUT").map(PathBuf::from);

    let health = check_health(&endpoint, &ca_path, &tls_domain).await?;
    let output = match mode.as_str() {
        "health" => json!({
            "phase": "health",
            "health": health,
        }),
        "prepare" => prepare(&endpoint, &ca_path, &tls_domain, health).await?,
        "verify" => verify(&endpoint, &ca_path, &tls_domain, health).await?,
        other => return Err(format!("unknown probe mode: {other}").into()),
    };
    let encoded = serde_json::to_vec_pretty(&output)?;
    if let Some(path) = output_path {
        fs::write(path, encoded)?;
    } else {
        println!("{}", String::from_utf8(encoded)?);
    }
    Ok(())
}

async fn prepare(
    endpoint: &str,
    ca_path: &Path,
    tls_domain: &str,
    health: &'static str,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let project_id = project_id()?;
    let client = new_client(endpoint, ca_path, tls_domain).await?;
    let cancel = CancellationToken::new();

    let project = client
        .execute_command(
            &envelope(
                project_id,
                None,
                Command::CreateProject {
                    name: "Launchd Restart".to_owned(),
                    time_zone: "UTC".to_owned(),
                },
            ),
            None,
            &cancel,
        )
        .await?;
    let task = client
        .execute_command(
            &envelope(
                project_id,
                Some(project.revision),
                task_command("Before restart"),
            ),
            None,
            &cancel,
        )
        .await?;
    let snapshot = client.get_snapshot(project_id, None, &cancel).await?;
    if snapshot.project.current_revision != task.revision || snapshot.tasks.len() != 1 {
        return Err("prepared snapshot did not match the created state".into());
    }

    Ok(json!({
        "phase": "prepared",
        "health": health,
        "project_id": project_id,
        "revision": task.revision,
        "tasks": snapshot.tasks.len(),
    }))
}

async fn verify(
    endpoint: &str,
    ca_path: &Path,
    tls_domain: &str,
    health: &'static str,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let project_id = project_id()?;

    wait_for_event(endpoint, ca_path, tls_domain, project_id, 1, 2).await?;
    let reader = new_client(endpoint, ca_path, tls_domain).await?;
    let cancel = CancellationToken::new();
    let restored = reader.get_snapshot(project_id, None, &cancel).await?;
    if restored.project.current_revision != 2 || restored.tasks.len() != 1 {
        return Err("restored snapshot did not preserve the pre-restart revision and task".into());
    }

    let task = reader
        .execute_command(
            &envelope(project_id, Some(2), task_command("After restart")),
            None,
            &cancel,
        )
        .await?;
    if task.revision != 3 {
        return Err(format!("expected revision 3 after restart, got {}", task.revision).into());
    }

    wait_for_event(endpoint, ca_path, tls_domain, project_id, 2, 3).await?;
    let final_snapshot = reader.get_snapshot(project_id, None, &cancel).await?;
    if final_snapshot.project.current_revision != 3 || final_snapshot.tasks.len() != 2 {
        return Err("final snapshot did not contain both tasks at revision 3".into());
    }

    Ok(json!({
        "phase": "verified",
        "health": health,
        "project_id": project_id,
        "replayed_pre_restart_event": true,
        "snapshot_revision_before_restart": 2,
        "snapshot_tasks_before_restart": 1,
        "new_revision": task.revision,
        "snapshot_tasks_after_restart": final_snapshot.tasks.len(),
        "event_revision_after_restart": 3,
    }))
}

async fn check_health(
    endpoint: &str,
    ca_path: &Path,
    tls_domain: &str,
) -> Result<&'static str, Box<dyn std::error::Error>> {
    let channel = connect_channel(endpoint, ca_path, tls_domain).await?;
    let mut client = HealthClient::new(channel);
    let response = client
        .check(HealthCheckRequest {
            service: SERVICE_NAME.to_owned(),
        })
        .await?;
    if response.into_inner().status == ServingStatus::Serving as i32 {
        Ok("SERVING")
    } else {
        Err("health service is not serving".into())
    }
}

async fn wait_for_event(
    endpoint: &str,
    ca_path: &Path,
    tls_domain: &str,
    project_id: Uuid,
    since_revision: u64,
    expected_revision: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let channel = connect_channel(endpoint, ca_path, tls_domain).await?;
    let mut service = KshiftServiceClient::new(channel);
    let token = required_env("KSHIFT_TOKEN")?;
    let mut request = Request::new(v1::WatchProjectChangesRequest {
        project_id: project_id.to_string(),
        since_revision,
    });
    request
        .metadata_mut()
        .insert("authorization", format!("Bearer {token}").parse()?);
    let mut stream = service.watch_project_changes(request).await?.into_inner();
    let observed = tokio::time::timeout(Duration::from_secs(10), async {
        while let Some(response) = stream.message().await? {
            let Some(v1::watch_project_changes_response::Payload::Event(event)) = response.payload
            else {
                continue;
            };
            if event.revision == expected_revision {
                return Ok::<bool, tonic::Status>(true);
            }
        }
        Ok::<bool, tonic::Status>(false)
    })
    .await
    .unwrap_or(Ok(false))?;
    if observed {
        Ok(())
    } else {
        Err(format!("event revision {expected_revision} was not delivered").into())
    }
}

async fn connect_channel(
    endpoint: &str,
    ca_path: &Path,
    tls_domain: &str,
) -> Result<Channel, Box<dyn std::error::Error>> {
    let ca_pem = fs::read(ca_path)?;
    let tls = ClientTlsConfig::new()
        .ca_certificate(Certificate::from_pem(ca_pem))
        .domain_name(tls_domain.to_owned());
    let mut last_error = None;
    for _ in 0..100 {
        match Endpoint::from_shared(endpoint.to_owned())?
            .tls_config(tls.clone())?
            .connect_timeout(Duration::from_secs(2))
            .connect()
            .await
        {
            Ok(channel) => return Ok(channel),
            Err(error) => last_error = Some(error.to_string()),
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Err(format!("server did not become reachable: {last_error:?}").into())
}

async fn new_client(
    endpoint: &str,
    ca_path: &Path,
    tls_domain: &str,
) -> Result<KshiftClient, Box<dyn std::error::Error>> {
    let config = ClientConfig::new(
        endpoint.to_owned(),
        fs::read(ca_path)?,
        Some(tls_domain.to_owned()),
        Duration::from_secs(10),
        MAX_RESPONSE_BYTES,
    )?;
    let client = KshiftClient::new(config)?;
    let token = AuthToken::new(required_env("KSHIFT_TOKEN")?)?;
    client.set_token(token).await;
    Ok(client)
}

fn envelope(project_id: Uuid, expected_revision: Option<u64>, command: Command) -> CommandEnvelope {
    CommandEnvelope {
        client_id: Uuid::new_v4(),
        command_id: Uuid::new_v4(),
        project_id,
        expected_revision,
        command,
    }
}

fn task_command(title: &str) -> Command {
    Command::CreateTask {
        task_id: Uuid::new_v4(),
        title: title.to_owned(),
        description_markdown: "launchd restart probe".to_owned(),
        status: TaskStatus::Todo,
        priority: TaskPriority::Medium,
        assignee_ids: Vec::new(),
        planned_on: NaiveDate::from_ymd_opt(2026, 11, 14).expect("valid fixture date"),
        starts_on: None,
        due_on: None,
        tags: vec!["launchd".to_owned()],
        parent_task_id: None,
        dependency_task_ids: Vec::new(),
    }
}

fn project_id() -> Result<Uuid, Box<dyn std::error::Error>> {
    Ok(Uuid::parse_str(&required_env("KSHIFT_PROJECT_ID")?)?)
}

fn required_env(name: &str) -> Result<String, Box<dyn std::error::Error>> {
    env::var(name).map_err(|_| format!("{name} is required").into())
}
