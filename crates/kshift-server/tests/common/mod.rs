#![allow(dead_code)]

use std::{collections::HashMap, str::FromStr, time::Duration};

use contract::{v1, v1::command_envelope::Command as ProtoCommand};
use kshift_server::{
    auth::TokenAuthenticator,
    config::{ApiLimits, ApiTimeouts, DatabaseConfig},
    db, migration,
    notifications::NotificationHub,
    service::{ApiSettings, KshiftApi},
};
use sqlx::{
    postgres::{PgConnectOptions, PgPoolOptions},
    ConnectOptions, PgPool,
};
use tonic::Request;
use uuid::Uuid;

pub struct TestDatabase {
    pub pool: PgPool,
    admin_url: String,
    database_name: String,
}

impl TestDatabase {
    pub async fn create() -> Option<Self> {
        Self::create_with_max_connections(8).await
    }

    pub async fn create_with_max_connections(max_connections: u32) -> Option<Self> {
        let admin_url = match std::env::var("TEST_DATABASE_URL") {
            Ok(value) => value,
            Err(_) => {
                eprintln!("TEST_DATABASE_URL is not set; PostgreSQL integration tests are skipped");
                return None;
            }
        };
        let database_name = format!("kshift_test_{}", Uuid::new_v4().simple());
        let maintenance = maintenance_pool(&admin_url).await;
        let statement = format!("CREATE DATABASE \"{database_name}\"");
        sqlx::query(&statement)
            .execute(&maintenance)
            .await
            .expect("test database should be created");
        maintenance.close().await;

        let test_options = PgConnectOptions::from_str(&admin_url)
            .expect("TEST_DATABASE_URL should parse")
            .database(&database_name);
        let config = DatabaseConfig {
            url: test_options.to_url_lossy().to_string(),
            min_connections: 1,
            max_connections,
            acquire_timeout: Duration::from_secs(5),
            statement_timeout: Duration::from_secs(15),
            lock_timeout: Duration::from_secs(5),
            idle_in_transaction_timeout: Duration::from_secs(30),
        };
        let pool = db::connect(&config)
            .await
            .expect("test database should connect");
        migration::run(&pool)
            .await
            .expect("test migrations should pass");

        Some(Self {
            pool,
            admin_url,
            database_name,
        })
    }

    pub async fn seed_user(&self, user_id: Uuid, display_name: &str, is_admin: bool) {
        sqlx::query(
            r#"
            INSERT INTO kshift.app_user (id, display_name, is_admin, is_active)
            VALUES ($1, $2, $3, true)
            "#,
        )
        .bind(user_id)
        .bind(display_name)
        .bind(is_admin)
        .execute(&self.pool)
        .await
        .expect("test user should be inserted");
    }

    pub async fn cleanup(self) {
        self.pool.close().await;
        let maintenance = maintenance_pool(&self.admin_url).await;
        sqlx::query(
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()",
        )
        .bind(&self.database_name)
        .execute(&maintenance)
        .await
        .expect("test database sessions should terminate");
        let statement = format!("DROP DATABASE \"{}\"", self.database_name);
        sqlx::query(&statement)
            .execute(&maintenance)
            .await
            .expect("test database should be dropped");
        maintenance.close().await;
    }
}

pub struct TestApi {
    pub api: KshiftApi,
    pub tokens: HashMap<Uuid, String>,
}

impl TestApi {
    pub fn create(pool: PgPool, tokens: HashMap<Uuid, String>) -> Self {
        Self::create_with_limits(
            pool,
            tokens,
            ApiLimits {
                unary_rpc: 100,
                write_transactions: 8,
                event_streams: 32,
                streams_per_user: 1,
            },
        )
    }

    pub fn create_with_limits(
        pool: PgPool,
        tokens: HashMap<Uuid, String>,
        limits: ApiLimits,
    ) -> Self {
        let authenticator = TokenAuthenticator::from_entries(
            tokens
                .iter()
                .map(|(user_id, token)| (token.clone(), *user_id)),
        )
        .expect("test authenticator should build");
        let settings = ApiSettings {
            limits,
            timeouts: ApiTimeouts {
                unary_request: Duration::from_secs(15),
                write_transaction: Duration::from_secs(10),
            },
            heartbeat_interval: Duration::from_secs(1),
            event_batch_size: 128,
            event_channel_capacity: 64,
            retention_days: 7,
        };
        Self {
            api: KshiftApi::new(
                pool,
                authenticator,
                NotificationHub::new(256),
                settings,
                tokio_util::sync::CancellationToken::new(),
            ),
            tokens,
        }
    }

    pub fn token(&self, user_id: Uuid) -> &str {
        self.tokens
            .get(&user_id)
            .expect("test user token should exist")
    }
}

async fn maintenance_pool(admin_url: &str) -> PgPool {
    let options = PgConnectOptions::from_str(admin_url)
        .expect("TEST_DATABASE_URL should parse")
        .database("postgres");
    PgPoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .expect("PostgreSQL maintenance connection should open")
}

pub fn request<T>(message: T, token: &str) -> Request<T> {
    let mut request = Request::new(message);
    request
        .metadata_mut()
        .insert("authorization", format!("Bearer {token}").parse().unwrap());
    request
}

pub fn create_project(project_id: Uuid, command_id: Uuid, name: &str) -> v1::ExecuteCommandRequest {
    execute_envelope(
        project_id,
        command_id,
        0,
        ProtoCommand::CreateProject(v1::CreateProjectCommand {
            name: name.to_owned(),
            time_zone: "UTC".to_owned(),
        }),
    )
}

pub fn add_member(
    project_id: Uuid,
    command_id: Uuid,
    user_id: Uuid,
    role: v1::ProjectRole,
    expected_revision: u64,
) -> v1::ExecuteCommandRequest {
    execute_envelope(
        project_id,
        command_id,
        expected_revision,
        ProtoCommand::AddProjectMember(v1::AddProjectMemberCommand {
            user_id: user_id.to_string(),
            role: role as i32,
        }),
    )
}

#[allow(clippy::too_many_arguments)]
pub fn create_task(
    project_id: Uuid,
    command_id: Uuid,
    _task_id: Uuid,
    title: &str,
    description: &str,
    expected_revision: u64,
) -> v1::ExecuteCommandRequest {
    execute_envelope(
        project_id,
        command_id,
        expected_revision,
        ProtoCommand::CreateTask(v1::CreateTaskCommand {
            draft: Some(v1::TaskDraft {
                title: title.to_owned(),
                description_markdown: description.to_owned(),
                status: v1::TaskStatus::Todo as i32,
                priority: v1::TaskPriority::Medium as i32,
                assignee_ids: Vec::new(),
                planned_on: "2026-11-13".to_owned(),
                starts_on: None,
                due_on: None,
                tags: Vec::new(),
                parent_task_id: None,
                dependency_task_ids: Vec::new(),
            }),
        }),
    )
}

pub fn create_task_with_assignees(
    project_id: Uuid,
    command_id: Uuid,
    title: &str,
    expected_revision: u64,
    assignee_ids: Vec<Uuid>,
) -> v1::ExecuteCommandRequest {
    execute_envelope(
        project_id,
        command_id,
        expected_revision,
        ProtoCommand::CreateTask(v1::CreateTaskCommand {
            draft: Some(v1::TaskDraft {
                title: title.to_owned(),
                description_markdown: String::new(),
                status: v1::TaskStatus::Todo as i32,
                priority: v1::TaskPriority::Medium as i32,
                assignee_ids: assignee_ids.into_iter().map(|id| id.to_string()).collect(),
                planned_on: "2026-11-13".to_owned(),
                starts_on: None,
                due_on: None,
                tags: Vec::new(),
                parent_task_id: None,
                dependency_task_ids: Vec::new(),
            }),
        }),
    )
}

pub fn update_task_title(
    project_id: Uuid,
    command_id: Uuid,
    task_id: Uuid,
    title: &str,
    expected_revision: u64,
    expected_entity_version: u64,
) -> v1::ExecuteCommandRequest {
    execute_envelope(
        project_id,
        command_id,
        expected_revision,
        ProtoCommand::UpdateTask(v1::UpdateTaskCommand {
            task_id: task_id.to_string(),
            expected_entity_version,
            patch: Some(v1::TaskPatch {
                title: Some(title.to_owned()),
                description_markdown: None,
                status: None,
                priority: None,
                assignee_ids: None,
                planned_on: None,
                starts_on: None,
                due_on: None,
                tags: None,
                parent_task_id: None,
                dependency_task_ids: None,
            }),
        }),
    )
}

pub fn batch_update_status(
    project_id: Uuid,
    command_id: Uuid,
    items: Vec<(Uuid, u64)>,
    status: v1::TaskStatus,
    expected_revision: u64,
) -> v1::ExecuteCommandRequest {
    let mutations = items
        .into_iter()
        .map(|(task_id, expected_entity_version)| v1::TaskMutation {
            mutation: Some(v1::task_mutation::Mutation::UpdateTask(
                v1::UpdateTaskCommand {
                    task_id: task_id.to_string(),
                    expected_entity_version,
                    patch: Some(v1::TaskPatch {
                        title: None,
                        description_markdown: None,
                        status: Some(status as i32),
                        priority: None,
                        assignee_ids: None,
                        planned_on: None,
                        starts_on: None,
                        due_on: None,
                        tags: None,
                        parent_task_id: None,
                        dependency_task_ids: None,
                    }),
                },
            )),
        })
        .collect();
    execute_envelope(
        project_id,
        command_id,
        expected_revision,
        ProtoCommand::BatchUpdateTasks(v1::BatchUpdateTasksCommand { mutations }),
    )
}

pub fn response_revision(response: &v1::ExecuteCommandResponse) -> u64 {
    response
        .result
        .as_ref()
        .expect("command result should be present")
        .project_revision
}

pub fn created_task(response: v1::ExecuteCommandResponse) -> v1::Task {
    let event = response
        .result
        .and_then(|result| result.event)
        .expect("command result event should be present");
    let change = event
        .changes
        .into_iter()
        .next()
        .and_then(|change| change.change)
        .expect("event change should be present");
    match change {
        v1::change::Change::TaskUpserted(change) => {
            change.task.expect("task upsert should contain a task")
        }
        other => panic!("expected task upsert, got {other:?}"),
    }
}

fn execute_envelope(
    project_id: Uuid,
    command_id: Uuid,
    expected_revision: u64,
    command: ProtoCommand,
) -> v1::ExecuteCommandRequest {
    v1::ExecuteCommandRequest {
        command: Some(v1::CommandEnvelope {
            client_id: Uuid::new_v4().to_string(),
            command_id: command_id.to_string(),
            project_id: project_id.to_string(),
            expected_project_revision: Some(expected_revision),
            command: Some(command),
        }),
    }
}
