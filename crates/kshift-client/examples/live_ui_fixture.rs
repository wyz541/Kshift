use std::{env, fs, path::PathBuf, time::Duration};

use chrono::NaiveDate;
use domain::{Command, CommandEnvelope, ProjectRole, TaskPriority, TaskStatus};
use kshift_client::{AuthToken, ClientConfig, KshiftClient, MAX_RESPONSE_BYTES};
use serde_json::json;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

const ALPHA_PROJECT_ID: u128 = 0x11111111_2222_4333_8444_555555555555;
const BETA_PROJECT_ID: u128 = 0x44444444_5555_4666_8777_888888888888;

fn required_env(name: &str) -> Result<String, Box<dyn std::error::Error>> {
    env::var(name).map_err(|_| format!("{name} is required").into())
}

fn argument(args: &[String], name: &str) -> Option<PathBuf> {
    args.iter()
        .position(|value| value == name)
        .and_then(|position| args.get(position + 1))
        .map(PathBuf::from)
}

fn envelope(project_id: Uuid, revision: Option<u64>, command: Command) -> CommandEnvelope {
    CommandEnvelope {
        client_id: Uuid::new_v4(),
        command_id: Uuid::new_v4(),
        project_id,
        expected_revision: revision,
        command,
    }
}

fn parse_date(name: &str) -> Result<NaiveDate, Box<dyn std::error::Error>> {
    Ok(NaiveDate::parse_from_str(&required_env(name)?, "%Y-%m-%d")?)
}

#[allow(clippy::too_many_arguments)]
async fn create_task(
    client: &KshiftClient,
    cancel: &CancellationToken,
    project_id: Uuid,
    revision: u64,
    title: &str,
    description: &str,
    status: TaskStatus,
    priority: TaskPriority,
    assignee_ids: Vec<Uuid>,
    date: NaiveDate,
) -> Result<u64, Box<dyn std::error::Error>> {
    let outcome = client
        .execute_command(
            &envelope(
                project_id,
                Some(revision),
                Command::CreateTask {
                    task_id: Uuid::new_v4(),
                    title: title.to_owned(),
                    description_markdown: description.to_owned(),
                    status,
                    priority,
                    assignee_ids,
                    planned_on: date,
                    starts_on: None,
                    due_on: Some(date),
                    tags: vec!["p0-e2e".to_owned()],
                    parent_task_id: None,
                    dependency_task_ids: Vec::new(),
                },
            ),
            None,
            cancel,
        )
        .await?;
    Ok(outcome.revision)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    let endpoint = required_env("KSHIFT_ENDPOINT")?;
    let ca_path = required_env("KSHIFT_CA_PATH")?;
    let token = required_env("KSHIFT_TOKEN")?;
    let actor_id = Uuid::parse_str(&required_env("KSHIFT_ACTOR_ID")?)?;
    let second_user_id = Uuid::parse_str(&required_env("KSHIFT_E2E_SECOND_USER_ID")?)?;
    let alpha_date = parse_date("KSHIFT_E2E_PRIMARY_DATE")?;
    let beta_date = parse_date("KSHIFT_E2E_SECONDARY_DATE")?;

    let config = ClientConfig::new(
        endpoint,
        fs::read(ca_path)?,
        Some("localhost".to_owned()),
        Duration::from_secs(10),
        MAX_RESPONSE_BYTES,
    )?;
    let client = KshiftClient::new(config)?;
    client.set_token(AuthToken::new(token)?).await;
    let cancel = CancellationToken::new();

    let alpha_project_id = Uuid::from_u128(ALPHA_PROJECT_ID);
    let beta_project_id = Uuid::from_u128(BETA_PROJECT_ID);

    let alpha_project = client
        .execute_command(
            &envelope(
                alpha_project_id,
                None,
                Command::CreateProject {
                    name: "Alpha Project".to_owned(),
                    time_zone: "Pacific/Kiritimati".to_owned(),
                },
            ),
            None,
            &cancel,
        )
        .await?;
    let alpha_member = client
        .execute_command(
            &envelope(
                alpha_project_id,
                Some(alpha_project.revision),
                Command::AddProjectMember {
                    user_id: second_user_id,
                    role: ProjectRole::Editor,
                },
            ),
            None,
            &cancel,
        )
        .await?;
    let mut alpha_revision = create_task(
        &client,
        &cancel,
        alpha_project_id,
        alpha_member.revision,
        "Shared roadmap task",
        "Shared by both project members.",
        TaskStatus::Todo,
        TaskPriority::High,
        vec![actor_id, second_user_id],
        alpha_date,
    )
    .await?;
    alpha_revision = create_task(
        &client,
        &cancel,
        alpha_project_id,
        alpha_revision,
        "Alpha review task",
        "Blocked work owned by the second member.",
        TaskStatus::Blocked,
        TaskPriority::Medium,
        vec![second_user_id],
        alpha_date,
    )
    .await?;
    alpha_revision = create_task(
        &client,
        &cancel,
        alpha_project_id,
        alpha_revision,
        "Alpha done task",
        "Completed work owned by the actor.",
        TaskStatus::Done,
        TaskPriority::Low,
        vec![actor_id],
        alpha_date,
    )
    .await?;

    let beta_project = client
        .execute_command(
            &envelope(
                beta_project_id,
                None,
                Command::CreateProject {
                    name: "Beta Project".to_owned(),
                    time_zone: "America/Los_Angeles".to_owned(),
                },
            ),
            None,
            &cancel,
        )
        .await?;
    let beta_member = client
        .execute_command(
            &envelope(
                beta_project_id,
                Some(beta_project.revision),
                Command::AddProjectMember {
                    user_id: second_user_id,
                    role: ProjectRole::Editor,
                },
            ),
            None,
            &cancel,
        )
        .await?;
    let beta_revision = create_task(
        &client,
        &cancel,
        beta_project_id,
        beta_member.revision,
        "Beta roadmap task",
        "Task isolated in the secondary project.",
        TaskStatus::Todo,
        TaskPriority::Medium,
        vec![actor_id],
        beta_date,
    )
    .await?;

    let alpha_snapshot = client.get_snapshot(alpha_project_id, None, &cancel).await?;
    let beta_snapshot = client.get_snapshot(beta_project_id, None, &cancel).await?;
    let summary = json!({
        "actor_id": actor_id,
        "second_user_id": second_user_id,
        "alpha_project_id": alpha_project_id,
        "alpha_project_name": "Alpha Project",
        "alpha_time_zone": "Pacific/Kiritimati",
        "alpha_date": alpha_date,
        "alpha_revision": alpha_revision,
        "alpha_audit_entries": alpha_snapshot.audit.len(),
        "beta_project_id": beta_project_id,
        "beta_project_name": "Beta Project",
        "beta_time_zone": "America/Los_Angeles",
        "beta_date": beta_date,
        "beta_revision": beta_revision,
        "beta_audit_entries": beta_snapshot.audit.len()
    });
    if let Some(path) = argument(&args, "--summary-file") {
        fs::write(path, serde_json::to_vec_pretty(&summary)?)?;
    }
    println!("{summary}");
    Ok(())
}
