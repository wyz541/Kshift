use std::{env, fs, path::PathBuf, time::Duration};

use chrono::Local;
use domain::{
    Change, Command, CommandEnvelope, Maybe, TaskMutation, TaskPatch, TaskPriority, TaskStatus,
};
use kshift_client::{AuthToken, ClientConfig, CommandOutcome, KshiftClient, MAX_RESPONSE_BYTES};
use serde_json::json;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

const PROJECT_ID: u128 = 0x11111111_2222_4333_8444_555555555555;

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

fn update_status(task_id: Uuid, version: u64, status: TaskStatus) -> TaskMutation {
    TaskMutation::UpdateTask {
        task_id,
        expected_entity_version: version,
        patch: TaskPatch {
            status: Maybe::Value(status),
            ..TaskPatch::default()
        },
    }
}

fn created_task_id(outcome: &CommandOutcome) -> Result<Uuid, Box<dyn std::error::Error>> {
    match outcome.event.changes.first() {
        Some(Change::TaskCreated { task } | Change::TaskUpdated { task }) => Ok(task.id),
        _ => Err("create_task did not return a task event".into()),
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    let endpoint = required_env("KSHIFT_ENDPOINT")?;
    let ca_path = required_env("KSHIFT_CA_PATH")?;
    let token = required_env("KSHIFT_TOKEN")?;
    let actor_id = Uuid::parse_str(&required_env("KSHIFT_ACTOR_ID")?)?;

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

    let project_id = Uuid::from_u128(PROJECT_ID);
    let today = Local::now().date_naive();

    let project = client
        .execute_command(
            &envelope(
                project_id,
                None,
                Command::CreateProject {
                    name: "Live Kshift".to_owned(),
                    time_zone: "Asia/Shanghai".to_owned(),
                },
            ),
            None,
            &cancel,
        )
        .await?;

    let first_task = client
        .execute_command(
            &envelope(
                project_id,
                Some(project.revision),
                Command::CreateTask {
                    task_id: Uuid::new_v4(),
                    title: "Live history task".to_owned(),
                    description_markdown: "Created by the live UI fixture.".to_owned(),
                    status: TaskStatus::Todo,
                    priority: TaskPriority::High,
                    assignee_ids: vec![actor_id],
                    planned_on: today,
                    starts_on: None,
                    due_on: Some(today),
                    tags: vec!["live-e2e".to_owned()],
                    parent_task_id: None,
                    dependency_task_ids: Vec::new(),
                },
            ),
            None,
            &cancel,
        )
        .await?;
    let task_one = created_task_id(&first_task)?;

    let updated = client
        .execute_command(
            &envelope(
                project_id,
                Some(first_task.revision),
                Command::UpdateTask {
                    task_id: task_one,
                    expected_entity_version: 1,
                    patch: TaskPatch {
                        status: Maybe::Value(TaskStatus::Done),
                        priority: Maybe::Value(TaskPriority::Urgent),
                        ..TaskPatch::default()
                    },
                },
            ),
            None,
            &cancel,
        )
        .await?;

    let second_task = client
        .execute_command(
            &envelope(
                project_id,
                Some(updated.revision),
                Command::CreateTask {
                    task_id: Uuid::new_v4(),
                    title: "Review live audit".to_owned(),
                    description_markdown: "Checks project audit mapping.".to_owned(),
                    status: TaskStatus::Todo,
                    priority: TaskPriority::Medium,
                    assignee_ids: vec![actor_id],
                    planned_on: today,
                    starts_on: None,
                    due_on: Some(today),
                    tags: vec!["audit".to_owned()],
                    parent_task_id: None,
                    dependency_task_ids: Vec::new(),
                },
            ),
            None,
            &cancel,
        )
        .await?;
    let task_two = created_task_id(&second_task)?;

    let batched = client
        .execute_command(
            &envelope(
                project_id,
                Some(second_task.revision),
                Command::BatchUpdateTasks {
                    mutations: vec![
                        update_status(task_one, 2, TaskStatus::Done),
                        update_status(task_two, 1, TaskStatus::InProgress),
                    ],
                },
            ),
            None,
            &cancel,
        )
        .await?;

    let snapshot = client.get_snapshot(project_id, None, &cancel).await?;
    if snapshot.project.current_revision != batched.revision || snapshot.audit.len() < 6 {
        return Err("live UI fixture did not produce the expected audit snapshot".into());
    }

    let summary = json!({
        "project_id": project_id,
        "project_name": "Live Kshift",
        "task_id": task_one,
        "task_title": "Live history task",
        "second_task_id": task_two,
        "revision": snapshot.project.current_revision,
        "audit_entries": snapshot.audit.len(),
        "task_history_entries": snapshot.audit.iter().filter(|entry| entry.task_id == Some(task_one)).count()
    });
    if let Some(path) = argument(&args, "--summary-file") {
        fs::write(path, serde_json::to_vec_pretty(&summary)?)?;
    }
    println!("{summary}");
    Ok(())
}
