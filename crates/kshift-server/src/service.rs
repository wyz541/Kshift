use std::{collections::HashMap, pin::Pin, sync::Arc, time::Duration};

use chrono::{DateTime, NaiveDate, Utc};
use contract::{
    change_event_to_proto, collapse_change_event, parse_execute_command, project_member_to_proto,
    project_snapshot_to_proto, project_summary_to_proto, task_to_proto, v1, ApiError,
    ParsedCommand,
};
use domain::{
    Change, ChangeEvent, Command, ProjectMember, ProjectRole, ProjectSnapshot, Task, TaskPriority,
    TaskStatus, SCHEMA_VERSION,
};
use futures_util::Stream;
use prost::Message;
use sqlx::{PgPool, Postgres, Transaction};
use tokio::sync::{broadcast, mpsc, Semaphore};
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::sync::CancellationToken;
use tonic::{Request, Response, Status};
use tracing::Instrument;
use uuid::Uuid;

use crate::{
    auth::{load_user, AuthenticatedUser, TokenAuthenticator},
    config::{ApiLimits, ApiTimeouts},
    notifications::{NotificationHub, NOTIFICATION_CHANNEL},
};

const IDEMPOTENCY_RETENTION_DAYS: i32 = 7;
const MAX_EVENT_BYTES: usize = 256 * 1024;

#[derive(Clone, Debug)]
pub struct ApiSettings {
    pub limits: ApiLimits,
    pub timeouts: ApiTimeouts,
    pub heartbeat_interval: Duration,
    pub event_batch_size: i64,
    pub event_channel_capacity: usize,
    pub retention_days: i32,
}

#[derive(Clone)]
pub struct KshiftApi {
    inner: Arc<ApiInner>,
}

struct ApiInner {
    pool: PgPool,
    auth: TokenAuthenticator,
    notifications: NotificationHub,
    settings: ApiSettings,
    shutdown: CancellationToken,
    rpc_slots: Arc<Semaphore>,
    write_slots: Arc<Semaphore>,
    stream_slots: Arc<Semaphore>,
    user_streams: tokio::sync::Mutex<HashMap<Uuid, Arc<Semaphore>>>,
}

impl KshiftApi {
    pub fn new(
        pool: PgPool,
        auth: TokenAuthenticator,
        notifications: NotificationHub,
        settings: ApiSettings,
        shutdown: CancellationToken,
    ) -> Self {
        Self {
            inner: Arc::new(ApiInner {
                pool,
                auth,
                notifications,
                rpc_slots: Arc::new(Semaphore::new(settings.limits.unary_rpc)),
                write_slots: Arc::new(Semaphore::new(settings.limits.write_transactions)),
                stream_slots: Arc::new(Semaphore::new(settings.limits.event_streams)),
                user_streams: tokio::sync::Mutex::new(HashMap::new()),
                settings,
                shutdown,
            }),
        }
    }

    pub fn pool(&self) -> &PgPool {
        &self.inner.pool
    }

    async fn authenticate<T>(&self, request: &Request<T>) -> Result<AuthenticatedUser, ApiError> {
        let user_id = self.inner.auth.authenticate_metadata(request.metadata())?;
        load_user(&self.inner.pool, user_id).await
    }

    async fn acquire_rpc_slot(&self) -> Result<tokio::sync::OwnedSemaphorePermit, ApiError> {
        self.inner
            .rpc_slots
            .clone()
            .try_acquire_owned()
            .map_err(|_| ApiError::ResourceExhausted("RPC concurrency limit reached".to_owned()))
    }

    async fn acquire_stream_slot(&self) -> Result<tokio::sync::OwnedSemaphorePermit, ApiError> {
        self.inner
            .stream_slots
            .clone()
            .try_acquire_owned()
            .map_err(|_| {
                ApiError::ResourceExhausted("event stream concurrency limit reached".to_owned())
            })
    }

    async fn acquire_user_stream_slot(
        &self,
        user_id: Uuid,
    ) -> Result<tokio::sync::OwnedSemaphorePermit, ApiError> {
        let semaphore = {
            let mut streams = self.inner.user_streams.lock().await;
            streams
                .entry(user_id)
                .or_insert_with(|| {
                    Arc::new(Semaphore::new(self.inner.settings.limits.streams_per_user))
                })
                .clone()
        };
        semaphore.try_acquire_owned().map_err(|_| {
            ApiError::ResourceExhausted("client event stream limit reached".to_owned())
        })
    }

    async fn snapshot(
        &self,
        actor: &AuthenticatedUser,
        project_id: Uuid,
    ) -> Result<ProjectSnapshot, ApiError> {
        let mut tx = self
            .inner
            .pool
            .begin()
            .await
            .map_err(|error| database_error(error, "begin snapshot transaction"))?;
        sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            .execute(&mut *tx)
            .await
            .map_err(|error| database_error(error, "configure snapshot transaction"))?;

        let project = load_authorized_project(&mut tx, actor, project_id, false).await?;
        let members = sqlx::query_as::<_, MemberRow>(
            r#"
            SELECT pm.user_id, u.display_name, pm.role
            FROM kshift.project_member pm
            JOIN kshift.app_user u ON u.id = pm.user_id
            WHERE pm.project_id = $1
            ORDER BY u.display_name, pm.user_id
            "#,
        )
        .bind(project_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|error| database_error(error, "load project members"))?;
        let tasks = sqlx::query_as::<_, TaskRow>(
            r#"
            SELECT id, project_id, title, description, status, priority, assignee_id,
                   due_date, version, created_by, updated_by, created_at, updated_at
            FROM kshift.task
            WHERE project_id = $1 AND deleted_at IS NULL
            ORDER BY due_date NULLS LAST, created_at, id
            "#,
        )
        .bind(project_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|error| database_error(error, "load project tasks"))?;

        tx.commit()
            .await
            .map_err(|error| database_error(error, "commit snapshot transaction"))?;

        Ok(ProjectSnapshot {
            project: project.try_into_domain()?,
            members: members
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<Vec<_>, _>>()?,
            tasks: tasks
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<Vec<_>, _>>()?,
            generated_at: Utc::now(),
        })
    }

    async fn execute_transaction(
        &self,
        actor: &AuthenticatedUser,
        parsed: &ParsedCommand,
        request_id: Uuid,
    ) -> Result<v1::ExecuteCommandResponse, ApiError> {
        let mut tx = self
            .inner
            .pool
            .begin()
            .await
            .map_err(|error| database_error(error, "begin command transaction"))?;
        lock_command_key(&mut tx, parsed).await?;

        if let Some(existing) = load_existing_result(&mut tx, parsed).await? {
            validate_replay(actor, parsed, &existing)?;
            authorize_for_replay(
                &mut tx,
                actor,
                parsed.envelope.project_id,
                &parsed.envelope.command,
            )
            .await?;
            let response = v1::ExecuteCommandResponse::decode(existing.response_payload.as_slice())
                .map_err(|error| {
                    tracing::error!(
                        request_id = %request_id,
                        error = %error,
                        "stored command response is invalid"
                    );
                    ApiError::Internal
                })?;
            tx.rollback()
                .await
                .map_err(|error| database_error(error, "finish idempotent replay"))?;
            return Ok(response);
        }

        let response = match &parsed.envelope.command {
            Command::CreateProject { name } => {
                self.create_project(&mut tx, actor, parsed, name, request_id)
                    .await?
            }
            Command::AddProjectMember { user_id, role } => {
                self.add_project_member(&mut tx, actor, parsed, *user_id, *role, request_id)
                    .await?
            }
            Command::CreateTask {
                task_id,
                title,
                description,
                status,
                priority,
                assignee_id,
                due_date,
            } => {
                self.create_task(
                    &mut tx,
                    actor,
                    parsed,
                    *task_id,
                    title,
                    description,
                    *status,
                    *priority,
                    *assignee_id,
                    *due_date,
                    request_id,
                )
                .await?
            }
            Command::UpdateTask {
                task_id,
                expected_entity_version,
                patch,
            } => {
                self.update_task(
                    &mut tx,
                    actor,
                    parsed,
                    *task_id,
                    *expected_entity_version,
                    patch,
                    request_id,
                )
                .await?
            }
            Command::DeleteTask {
                task_id,
                expected_entity_version,
            } => {
                self.delete_task(
                    &mut tx,
                    actor,
                    parsed,
                    *task_id,
                    *expected_entity_version,
                    request_id,
                )
                .await?
            }
        };

        let response_payload = response.encode_to_vec();
        sqlx::query(
            r#"
            INSERT INTO kshift.command_result (
                client_id, command_id, project_id, actor_id, request_digest,
                response_payload, created_at, expires_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, now(), now() + make_interval(days => $7))
            "#,
        )
        .bind(parsed.envelope.client_id)
        .bind(parsed.envelope.command_id)
        .bind(parsed.envelope.project_id)
        .bind(actor.id)
        .bind(&parsed.request_digest)
        .bind(response_payload)
        .bind(IDEMPOTENCY_RETENTION_DAYS)
        .execute(&mut *tx)
        .await
        .map_err(|error| database_error(error, "store idempotent command result"))?;

        tx.commit()
            .await
            .map_err(|error| database_error(error, "commit command transaction"))?;
        Ok(response)
    }

    async fn create_project(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        actor: &AuthenticatedUser,
        parsed: &ParsedCommand,
        name: &str,
        _request_id: Uuid,
    ) -> Result<v1::ExecuteCommandResponse, ApiError> {
        if !actor.is_admin {
            return Err(ApiError::PermissionDenied);
        }
        let now = Utc::now();
        let project_id = parsed.envelope.project_id;
        sqlx::query(
            r#"
            INSERT INTO kshift.project (
                id, name, current_revision, created_by, created_at, updated_at
            )
            VALUES ($1, $2, 1, $3, $4, $4)
            "#,
        )
        .bind(project_id)
        .bind(name)
        .bind(actor.id)
        .bind(now)
        .execute(&mut **tx)
        .await
        .map_err(|error| command_database_error(error, "create project"))?;

        sqlx::query(
            r#"
            INSERT INTO kshift.project_member (project_id, user_id, role, created_at, updated_at)
            VALUES ($1, $2, 'owner', $3, $3)
            "#,
        )
        .bind(project_id)
        .bind(actor.id)
        .bind(now)
        .execute(&mut **tx)
        .await
        .map_err(|error| command_database_error(error, "create project owner"))?;

        let member = ProjectMember {
            user_id: actor.id,
            display_name: actor.display_name.clone(),
            role: ProjectRole::Owner,
        };
        let event = ChangeEvent {
            project_id,
            revision: 1,
            schema_version: SCHEMA_VERSION,
            command_id: parsed.envelope.command_id,
            occurred_at: now,
            change: Change::ProjectCreated {
                project_id,
                name: name.to_owned(),
            },
        };
        insert_event(tx, &event, self.inner.settings.retention_days).await?;
        insert_audit(
            tx,
            actor,
            parsed,
            "project",
            project_id,
            None,
            Some(serde_json::json!({
                "id": project_id,
                "name": name,
                "current_revision": 1
            })),
            now,
        )
        .await?;
        let snapshot = ProjectSnapshot {
            project: domain::Project {
                id: project_id,
                name: name.to_owned(),
                current_revision: 1,
                created_at: now,
                updated_at: now,
            },
            members: vec![member],
            tasks: Vec::new(),
            generated_at: now,
        };
        Ok(v1::ExecuteCommandResponse {
            revision: 1,
            result: Some(v1::execute_command_response::Result::CreateProject(
                v1::CreateProjectResult {
                    snapshot: Some(project_snapshot_to_proto(&snapshot)),
                },
            )),
        })
    }

    async fn add_project_member(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        actor: &AuthenticatedUser,
        parsed: &ParsedCommand,
        user_id: Uuid,
        role: ProjectRole,
        request_id: Uuid,
    ) -> Result<v1::ExecuteCommandResponse, ApiError> {
        let project_id = parsed.envelope.project_id;
        let project =
            lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision)
                .await?;
        let current_revision = project.current_revision_u64()?;
        let actor_role = project_role_for_actor(tx, actor, project_id).await?;
        if !actor_role.can_manage_members() {
            return Err(ApiError::PermissionDenied);
        }
        let target = sqlx::query_as::<_, UserNameRow>(
            "SELECT display_name FROM kshift.app_user WHERE id = $1 AND is_active = true",
        )
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|error| database_error(error, "load member user"))?
        .ok_or_else(|| {
            ApiError::InvalidArgument("member user is inactive or not found".to_owned())
        })?;

        let previous_role = sqlx::query_scalar::<_, String>(
            "SELECT role FROM kshift.project_member WHERE project_id = $1 AND user_id = $2",
        )
        .bind(project_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|error| database_error(error, "load previous member role"))?;
        let now = Utc::now();
        sqlx::query(
            r#"
            INSERT INTO kshift.project_member (project_id, user_id, role, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $4)
            ON CONFLICT (project_id, user_id) DO UPDATE SET
                role = EXCLUDED.role,
                updated_at = EXCLUDED.updated_at
            "#,
        )
        .bind(project_id)
        .bind(user_id)
        .bind(role_to_db(role))
        .bind(now)
        .execute(&mut **tx)
        .await
        .map_err(|error| command_database_error(error, "upsert project member"))?;

        let revision = bump_revision(tx, project_id, current_revision, now).await?;
        let member = ProjectMember {
            user_id,
            display_name: target.display_name,
            role,
        };
        insert_project_member_event_and_audit(
            tx,
            actor,
            parsed,
            project_id,
            &member,
            revision,
            now,
            previous_role,
            self.inner.settings.retention_days,
        )
        .await?;

        tracing::info!(
            request_id = %request_id,
            project_id = %project_id,
            revision,
            member_id = %user_id,
            "project member upserted"
        );
        Ok(v1::ExecuteCommandResponse {
            revision,
            result: Some(v1::execute_command_response::Result::AddProjectMember(
                v1::AddProjectMemberResult {
                    member: Some(project_member_to_proto(&member)),
                },
            )),
        })
    }

    #[allow(clippy::too_many_arguments)]
    async fn create_task(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        actor: &AuthenticatedUser,
        parsed: &ParsedCommand,
        task_id: Uuid,
        title: &str,
        description: &str,
        status: TaskStatus,
        priority: TaskPriority,
        assignee_id: Option<Uuid>,
        due_date: Option<NaiveDate>,
        request_id: Uuid,
    ) -> Result<v1::ExecuteCommandResponse, ApiError> {
        let project_id = parsed.envelope.project_id;
        let project =
            lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision)
                .await?;
        let current_revision = project.current_revision_u64()?;
        require_write_role(tx, actor, project_id).await?;
        if let Some(assignee_id) = assignee_id {
            require_active_user(tx, assignee_id).await?;
        }

        let now = Utc::now();
        sqlx::query(
            r#"
            INSERT INTO kshift.task (
                id, project_id, title, description, status, priority, assignee_id, due_date,
                version, created_by, updated_by, created_at, updated_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 1, $9, $9, $10, $10)
            "#,
        )
        .bind(task_id)
        .bind(project_id)
        .bind(title)
        .bind(description)
        .bind(status_to_db(status))
        .bind(priority_to_db(priority))
        .bind(assignee_id)
        .bind(due_date)
        .bind(actor.id)
        .bind(now)
        .execute(&mut **tx)
        .await
        .map_err(|error| command_database_error(error, "create task"))?;

        let revision = bump_revision(tx, project_id, current_revision, now).await?;
        let task = Task {
            id: task_id,
            project_id,
            title: title.to_owned(),
            description: description.to_owned(),
            status,
            priority,
            assignee_id,
            due_date,
            version: 1,
            created_by: actor.id,
            updated_by: actor.id,
            created_at: now,
            updated_at: now,
        };
        let event = ChangeEvent {
            project_id,
            revision,
            schema_version: SCHEMA_VERSION,
            command_id: parsed.envelope.command_id,
            occurred_at: now,
            change: Change::TaskCreated { task: task.clone() },
        };
        insert_event(tx, &event, self.inner.settings.retention_days).await?;
        insert_audit(
            tx,
            actor,
            parsed,
            "task",
            task_id,
            None,
            Some(serde_json::to_value(&task).map_err(|_| ApiError::Internal)?),
            now,
        )
        .await?;

        tracing::info!(
            request_id = %request_id,
            project_id = %project_id,
            revision,
            entity_id = %task_id,
            "task created"
        );
        Ok(v1::ExecuteCommandResponse {
            revision,
            result: Some(v1::execute_command_response::Result::CreateTask(
                v1::CreateTaskResult {
                    task: Some(task_to_proto(&task)),
                },
            )),
        })
    }

    #[allow(clippy::too_many_arguments)]
    async fn update_task(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        actor: &AuthenticatedUser,
        parsed: &ParsedCommand,
        task_id: Uuid,
        expected_entity_version: u64,
        patch: &domain::TaskPatch,
        request_id: Uuid,
    ) -> Result<v1::ExecuteCommandResponse, ApiError> {
        let project_id = parsed.envelope.project_id;
        let project =
            lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision)
                .await?;
        let current_revision = project.current_revision_u64()?;
        require_write_role(tx, actor, project_id).await?;
        let existing = lock_task(tx, project_id, task_id, current_revision).await?;
        let existing_version = u64::try_from(existing.version).map_err(|_| ApiError::Internal)?;
        if existing_version != expected_entity_version {
            return Err(ApiError::Conflict {
                current_revision: Some(current_revision),
                entity_id: Some(task_id),
                current_entity_version: Some(existing_version),
            });
        }
        let before: Task = existing.clone().try_into()?;
        let updated = domain::update_task(&before, patch, actor.id).map_err(ApiError::from)?;
        if let Some(assignee_id) = updated.assignee_id {
            require_active_user(tx, assignee_id).await?;
        }

        sqlx::query(
            r#"
            UPDATE kshift.task SET
                title = $3,
                description = $4,
                status = $5,
                priority = $6,
                assignee_id = $7,
                due_date = $8,
                version = $9,
                updated_by = $10,
                updated_at = $11
            WHERE id = $1 AND project_id = $2 AND deleted_at IS NULL
            "#,
        )
        .bind(task_id)
        .bind(project_id)
        .bind(&updated.title)
        .bind(&updated.description)
        .bind(status_to_db(updated.status))
        .bind(priority_to_db(updated.priority))
        .bind(updated.assignee_id)
        .bind(updated.due_date)
        .bind(to_i64(updated.version, "task version")?)
        .bind(actor.id)
        .bind(updated.updated_at)
        .execute(&mut **tx)
        .await
        .map_err(|error| command_database_error(error, "update task"))?;

        let revision = bump_revision(tx, project_id, current_revision, updated.updated_at).await?;
        let event = ChangeEvent {
            project_id,
            revision,
            schema_version: SCHEMA_VERSION,
            command_id: parsed.envelope.command_id,
            occurred_at: updated.updated_at,
            change: Change::TaskUpdated {
                task: updated.clone(),
            },
        };
        insert_event(tx, &event, self.inner.settings.retention_days).await?;
        insert_audit(
            tx,
            actor,
            parsed,
            "task",
            task_id,
            Some(serde_json::to_value(&before).map_err(|_| ApiError::Internal)?),
            Some(serde_json::to_value(&updated).map_err(|_| ApiError::Internal)?),
            updated.updated_at,
        )
        .await?;

        tracing::info!(
            request_id = %request_id,
            project_id = %project_id,
            revision,
            entity_id = %task_id,
            entity_version = updated.version,
            "task updated"
        );
        Ok(v1::ExecuteCommandResponse {
            revision,
            result: Some(v1::execute_command_response::Result::UpdateTask(
                v1::UpdateTaskResult {
                    task: Some(task_to_proto(&updated)),
                },
            )),
        })
    }

    async fn delete_task(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        actor: &AuthenticatedUser,
        parsed: &ParsedCommand,
        task_id: Uuid,
        expected_entity_version: u64,
        request_id: Uuid,
    ) -> Result<v1::ExecuteCommandResponse, ApiError> {
        let project_id = parsed.envelope.project_id;
        let project =
            lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision)
                .await?;
        let current_revision = project.current_revision_u64()?;
        require_write_role(tx, actor, project_id).await?;
        let existing = lock_task(tx, project_id, task_id, current_revision).await?;
        let existing_version = u64::try_from(existing.version).map_err(|_| ApiError::Internal)?;
        if existing_version != expected_entity_version {
            return Err(ApiError::Conflict {
                current_revision: Some(current_revision),
                entity_id: Some(task_id),
                current_entity_version: Some(existing_version),
            });
        }
        let before: Task = existing.try_into()?;
        let now = Utc::now();
        let deleted_version = before.version.checked_add(1).ok_or(ApiError::Internal)?;
        sqlx::query(
            r#"
            UPDATE kshift.task SET
                version = $3,
                deleted_at = $4,
                deleted_by = $5,
                updated_by = $5,
                updated_at = $4
            WHERE id = $1 AND project_id = $2 AND deleted_at IS NULL
            "#,
        )
        .bind(task_id)
        .bind(project_id)
        .bind(to_i64(deleted_version, "task version")?)
        .bind(now)
        .bind(actor.id)
        .execute(&mut **tx)
        .await
        .map_err(|error| command_database_error(error, "delete task"))?;

        let revision = bump_revision(tx, project_id, current_revision, now).await?;
        let event = ChangeEvent {
            project_id,
            revision,
            schema_version: SCHEMA_VERSION,
            command_id: parsed.envelope.command_id,
            occurred_at: now,
            change: Change::TaskDeleted {
                task_id,
                version: deleted_version,
            },
        };
        insert_event(tx, &event, self.inner.settings.retention_days).await?;
        insert_audit(
            tx,
            actor,
            parsed,
            "task",
            task_id,
            Some(serde_json::to_value(&before).map_err(|_| ApiError::Internal)?),
            Some(serde_json::json!({
                "id": task_id,
                "version": deleted_version,
                "deleted_at": now
            })),
            now,
        )
        .await?;

        tracing::info!(
            request_id = %request_id,
            project_id = %project_id,
            revision,
            entity_id = %task_id,
            entity_version = deleted_version,
            "task deleted"
        );
        Ok(v1::ExecuteCommandResponse {
            revision,
            result: Some(v1::execute_command_response::Result::DeleteTask(
                v1::DeleteTaskResult {
                    task_id: task_id.to_string(),
                    version: deleted_version,
                },
            )),
        })
    }

    async fn watch(
        &self,
        actor: AuthenticatedUser,
        project_id: Uuid,
        since_revision: u64,
        request_id: Uuid,
    ) -> Result<
        Pin<Box<dyn Stream<Item = Result<v1::WatchProjectChangesResponse, Status>> + Send>>,
        ApiError,
    > {
        let stream_permit = self.acquire_stream_slot().await?;
        let user_permit = self.acquire_user_stream_slot(actor.id).await?;
        let notification_receiver = self.inner.notifications.subscribe();
        let (sender, receiver) = mpsc::channel(self.inner.settings.event_channel_capacity);
        let pool = self.inner.pool.clone();
        let shutdown = self.inner.shutdown.clone();
        let heartbeat_interval = self.inner.settings.heartbeat_interval;
        let batch_size = self.inner.settings.event_batch_size;

        tokio::spawn(async move {
            let _stream_permit = stream_permit;
            let _user_permit = user_permit;
            let mut notification_receiver = notification_receiver;
            let mut cursor = since_revision;
            let mut current_revision = since_revision;
            let mut heartbeat_due = false;
            let mut ticker = tokio::time::interval(heartbeat_interval);
            ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            ticker.tick().await;

            loop {
                let page = match fetch_event_page(
                    &pool,
                    &actor,
                    project_id,
                    cursor,
                    current_revision,
                    batch_size,
                )
                .await
                {
                    Ok(page) => page,
                    Err(error) => {
                        tracing::warn!(
                            request_id = %request_id,
                            project_id = %project_id,
                            error = %error,
                            "closing event stream after authorization or database failure"
                        );
                        let _ = sender.try_send(Err(error.to_status()));
                        return;
                    }
                };
                current_revision = page.current_revision;

                if let Some(reset) = page.reset {
                    let response = v1::WatchProjectChangesResponse {
                        payload: Some(v1::watch_project_changes_response::Payload::ResetRequired(
                            reset,
                        )),
                    };
                    let _ = sender.try_send(Ok(response));
                    return;
                }

                for event in page.events {
                    let response = v1::WatchProjectChangesResponse {
                        payload: Some(v1::watch_project_changes_response::Payload::Change(
                            contract::change_event_to_proto(&event),
                        )),
                    };
                    if sender.try_send(Ok(response)).is_err() {
                        tracing::warn!(
                            request_id = %request_id,
                            project_id = %project_id,
                            "closing slow event stream for backpressure"
                        );
                        return;
                    }
                    cursor = event.revision;
                }

                if heartbeat_due {
                    heartbeat_due = false;
                    let response = v1::WatchProjectChangesResponse {
                        payload: Some(v1::watch_project_changes_response::Payload::Heartbeat(
                            v1::Heartbeat {
                                revision: current_revision,
                                sent_at: Some(prost_types_timestamp(Utc::now())),
                            },
                        )),
                    };
                    if sender.try_send(Ok(response)).is_err() {
                        return;
                    }
                }

                tokio::select! {
                    _ = sender.closed() => return,
                    _ = shutdown.cancelled() => return,
                    _ = ticker.tick() => heartbeat_due = true,
                    result = notification_receiver.recv() => {
                        match result {
                            Ok(notified_project) if notified_project == project_id => {}
                            Ok(_) => {}
                            Err(broadcast::error::RecvError::Lagged(skipped)) => {
                                tracing::warn!(
                                    request_id = %request_id,
                                    project_id = %project_id,
                                    skipped,
                                    "notification receiver lagged; outbox will be replayed"
                                );
                            }
                            Err(broadcast::error::RecvError::Closed) => return,
                        }
                    }
                }
            }
        });

        Ok(Box::pin(ReceiverStream::new(receiver)))
    }
}

#[tonic::async_trait]
impl contract::KshiftService for KshiftApi {
    async fn list_projects(
        &self,
        request: Request<v1::ListProjectsRequest>,
    ) -> Result<Response<v1::ListProjectsResponse>, Status> {
        let request_id = Uuid::new_v4();
        let span = tracing::info_span!("grpc.list_projects", request_id = %request_id);
        self.list_projects_inner(request, request_id)
            .instrument(span)
            .await
            .map(Response::new)
            .map_err(|error| error.to_status())
    }

    async fn get_project_snapshot(
        &self,
        request: Request<v1::GetProjectSnapshotRequest>,
    ) -> Result<Response<v1::GetProjectSnapshotResponse>, Status> {
        let request_id = Uuid::new_v4();
        let span = tracing::info_span!(
            "grpc.get_project_snapshot",
            request_id = %request_id
        );
        self.get_snapshot_inner(request, request_id)
            .instrument(span)
            .await
            .map_err(|error| error.to_status())
    }

    async fn execute_command(
        &self,
        request: Request<v1::ExecuteCommandRequest>,
    ) -> Result<Response<v1::ExecuteCommandResponse>, Status> {
        let request_id = Uuid::new_v4();
        let span = tracing::info_span!("grpc.execute_command", request_id = %request_id);
        self.execute_command_inner(request, request_id)
            .instrument(span)
            .await
            .map_err(|error| error.to_status())
    }

    type WatchProjectChangesStream =
        Pin<Box<dyn Stream<Item = Result<v1::WatchProjectChangesResponse, Status>> + Send>>;

    async fn watch_project_changes(
        &self,
        request: Request<v1::WatchProjectChangesRequest>,
    ) -> Result<Response<Self::WatchProjectChangesStream>, Status> {
        let request_id = Uuid::new_v4();
        let span = tracing::info_span!("grpc.watch_project_changes", request_id = %request_id);
        self.watch_inner(request, request_id)
            .instrument(span)
            .await
            .map(Response::new)
            .map_err(|error| error.to_status())
    }
}

impl KshiftApi {
    async fn list_projects_inner(
        &self,
        request: Request<v1::ListProjectsRequest>,
        request_id: Uuid,
    ) -> Result<v1::ListProjectsResponse, ApiError> {
        let _rpc_permit = self.acquire_rpc_slot().await?;
        let actor = self.authenticate(&request).await?;
        let rows = tokio::time::timeout(
            self.inner.settings.timeouts.unary_request,
            load_project_summaries(&self.inner.pool, &actor),
        )
        .await
        .map_err(|_| ApiError::DeadlineExceeded)??;
        tracing::info!(
            request_id = %request_id,
            user_id = %actor.id,
            project_count = rows.len(),
            "project list completed"
        );
        Ok(v1::ListProjectsResponse {
            projects: rows
                .into_iter()
                .map(|(project, role)| project_summary_to_proto(&project, role))
                .collect(),
        })
    }

    async fn get_snapshot_inner(
        &self,
        request: Request<v1::GetProjectSnapshotRequest>,
        request_id: Uuid,
    ) -> Result<Response<v1::GetProjectSnapshotResponse>, ApiError> {
        let _rpc_permit = self.acquire_rpc_slot().await?;
        let actor = self.authenticate(&request).await?;
        tracing::info!(request_id = %request_id, user_id = %actor.id, "snapshot started");
        let project_id = parse_uuid(&request.into_inner().project_id, "project_id")?;
        let result = tokio::time::timeout(
            self.inner.settings.timeouts.unary_request,
            self.snapshot(&actor, project_id),
        )
        .await
        .map_err(|_| ApiError::DeadlineExceeded)??;
        tracing::info!(
            request_id = %request_id,
            user_id = %actor.id,
            project_id = %project_id,
            revision = result.project.current_revision,
            "snapshot completed"
        );
        Ok(Response::new(v1::GetProjectSnapshotResponse {
            snapshot: Some(project_snapshot_to_proto(&result)),
        }))
    }

    async fn execute_command_inner(
        &self,
        request: Request<v1::ExecuteCommandRequest>,
        request_id: Uuid,
    ) -> Result<Response<v1::ExecuteCommandResponse>, ApiError> {
        let _rpc_permit = self.acquire_rpc_slot().await?;
        let actor = self.authenticate(&request).await?;
        let parsed = parse_execute_command(request.get_ref())?;
        let command_name = parsed.envelope.command.name();
        tracing::info!(
            request_id = %request_id,
            user_id = %actor.id,
            project_id = %parsed.envelope.project_id,
            client_id = %parsed.envelope.client_id,
            command_id = %parsed.envelope.command_id,
            command = command_name,
            "command started"
        );

        let _write_permit = self
            .inner
            .write_slots
            .clone()
            .try_acquire_owned()
            .map_err(|_| {
                ApiError::ResourceExhausted("write transaction limit reached".to_owned())
            })?;
        let response = tokio::time::timeout(
            self.inner.settings.timeouts.write_transaction,
            self.execute_transaction(&actor, &parsed, request_id),
        )
        .await
        .map_err(|_| ApiError::DeadlineExceeded)??;

        tracing::info!(
            request_id = %request_id,
            user_id = %actor.id,
            project_id = %parsed.envelope.project_id,
            client_id = %parsed.envelope.client_id,
            command_id = %parsed.envelope.command_id,
            command = command_name,
            revision = response.revision,
            "command completed"
        );
        Ok(Response::new(response))
    }

    async fn watch_inner(
        &self,
        request: Request<v1::WatchProjectChangesRequest>,
        request_id: Uuid,
    ) -> Result<
        Pin<Box<dyn Stream<Item = Result<v1::WatchProjectChangesResponse, Status>> + Send>>,
        ApiError,
    > {
        let actor = self.authenticate(&request).await?;
        let request = request.into_inner();
        let project_id = parse_uuid(&request.project_id, "project_id")?;
        let role = self.project_role(&actor, project_id).await?;
        if !role.can_read() {
            return Err(ApiError::PermissionDenied);
        }
        tracing::info!(
            request_id = %request_id,
            user_id = %actor.id,
            project_id = %project_id,
            since_revision = request.since_revision,
            "event stream opened"
        );
        self.watch(actor, project_id, request.since_revision, request_id)
            .await
    }

    async fn project_role(
        &self,
        actor: &AuthenticatedUser,
        project_id: Uuid,
    ) -> Result<ProjectRole, ApiError> {
        let mut tx = self
            .inner
            .pool
            .begin()
            .await
            .map_err(|error| database_error(error, "begin authorization transaction"))?;
        let project = load_authorized_project(&mut tx, actor, project_id, false).await?;
        let role = project.role;
        tx.rollback()
            .await
            .map_err(|error| database_error(error, "finish authorization transaction"))?;
        Ok(role)
    }
}

// The remaining helpers are intentionally in this module: they hold the
// transaction boundaries that make revisions, audit, results and outbox atomic.

async fn lock_command_key(
    tx: &mut Transaction<'_, Postgres>,
    parsed: &ParsedCommand,
) -> Result<(), ApiError> {
    let key = format!(
        "{}:{}",
        parsed.envelope.client_id, parsed.envelope.command_id
    );
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(key)
        .execute(&mut **tx)
        .await
        .map_err(|error| database_error(error, "lock idempotency key"))?;
    Ok(())
}

async fn load_existing_result(
    tx: &mut Transaction<'_, Postgres>,
    parsed: &ParsedCommand,
) -> Result<Option<CommandResultRow>, ApiError> {
    sqlx::query_as::<_, CommandResultRow>(
        r#"
        SELECT project_id, actor_id, request_digest, response_payload
        FROM kshift.command_result
        WHERE client_id = $1 AND command_id = $2
        "#,
    )
    .bind(parsed.envelope.client_id)
    .bind(parsed.envelope.command_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|error| database_error(error, "load idempotency record"))
}

fn validate_replay(
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    existing: &CommandResultRow,
) -> Result<(), ApiError> {
    if existing.actor_id != actor.id
        || existing.project_id != parsed.envelope.project_id
        || existing.request_digest != parsed.request_digest
    {
        return Err(ApiError::AlreadyExists(
            "command_id was already used with a different request".to_owned(),
        ));
    }
    Ok(())
}

async fn authorize_for_replay(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    project_id: Uuid,
    command: &Command,
) -> Result<(), ApiError> {
    match command {
        Command::CreateProject { .. } => {
            if actor.is_admin {
                Ok(())
            } else {
                Err(ApiError::PermissionDenied)
            }
        }
        _ => {
            let role = project_role_for_actor(tx, actor, project_id).await?;
            if role.can_read() {
                Ok(())
            } else {
                Err(ApiError::PermissionDenied)
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
async fn insert_project_member_event_and_audit(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    project_id: Uuid,
    member: &ProjectMember,
    revision: u64,
    now: DateTime<Utc>,
    previous_role: Option<String>,
    retention_days: i32,
) -> Result<(), ApiError> {
    let event = ChangeEvent {
        project_id,
        revision,
        schema_version: SCHEMA_VERSION,
        command_id: parsed.envelope.command_id,
        occurred_at: now,
        change: Change::ProjectMemberUpserted {
            member: member.clone(),
        },
    };
    insert_event(tx, &event, retention_days).await?;
    insert_audit(
        tx,
        actor,
        parsed,
        "project_member",
        member.user_id,
        previous_role.map(|role| serde_json::json!({ "role": role })),
        Some(serde_json::json!({
            "user_id": member.user_id,
            "display_name": member.display_name,
            "role": role_to_db(member.role)
        })),
        now,
    )
    .await?;
    Ok(())
}

async fn insert_event(
    tx: &mut Transaction<'_, Postgres>,
    event: &ChangeEvent,
    retention_days: i32,
) -> Result<(), ApiError> {
    let payload = change_event_to_proto(event).encode_to_vec();
    if payload.len() > MAX_EVENT_BYTES {
        return Err(ApiError::FailedPrecondition(
            "event exceeds the configured size limit".to_owned(),
        ));
    }
    sqlx::query(
        r#"
        INSERT INTO kshift.change_event (
            project_id, revision, schema_version, command_id, payload, created_at, expires_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $6 + make_interval(days => $7))
        "#,
    )
    .bind(event.project_id)
    .bind(to_i64(event.revision, "event revision")?)
    .bind(event.schema_version as i32)
    .bind(event.command_id)
    .bind(payload)
    .bind(event.occurred_at)
    .bind(retention_days)
    .execute(&mut **tx)
    .await
    .map_err(|error| command_database_error(error, "insert outbox event"))?;

    sqlx::query("SELECT pg_notify($1, $2)")
        .bind(NOTIFICATION_CHANNEL)
        .bind(event.project_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|error| database_error(error, "notify outbox event"))?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn insert_audit(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    entity_type: &str,
    entity_id: Uuid,
    before_data: Option<serde_json::Value>,
    after_data: Option<serde_json::Value>,
    now: DateTime<Utc>,
) -> Result<(), ApiError> {
    sqlx::query(
        r#"
        INSERT INTO kshift.audit_log (
            id, project_id, actor_id, client_id, command_id, command_name,
            entity_type, entity_id, before_data, after_data, occurred_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(parsed.envelope.project_id)
    .bind(actor.id)
    .bind(parsed.envelope.client_id)
    .bind(parsed.envelope.command_id)
    .bind(parsed.envelope.command.name())
    .bind(entity_type)
    .bind(entity_id)
    .bind(before_data)
    .bind(after_data)
    .bind(now)
    .execute(&mut **tx)
    .await
    .map_err(|error| database_error(error, "insert audit record"))?;
    Ok(())
}

async fn bump_revision(
    tx: &mut Transaction<'_, Postgres>,
    project_id: Uuid,
    previous_revision: u64,
    now: DateTime<Utc>,
) -> Result<u64, ApiError> {
    let revision = sqlx::query_scalar::<_, i64>(
        r#"
        UPDATE kshift.project
        SET current_revision = current_revision + 1, updated_at = $2
        WHERE id = $1 AND current_revision = $3
        RETURNING current_revision
        "#,
    )
    .bind(project_id)
    .bind(now)
    .bind(to_i64(previous_revision, "project revision")?)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|error| database_error(error, "increment project revision"))?
    .ok_or(ApiError::Conflict {
        current_revision: Some(previous_revision),
        entity_id: None,
        current_entity_version: None,
    })?;
    u64::try_from(revision).map_err(|_| ApiError::Internal)
}

async fn load_project_summaries(
    pool: &PgPool,
    actor: &AuthenticatedUser,
) -> Result<Vec<(domain::Project, ProjectRole)>, ApiError> {
    let rows = if actor.is_admin {
        sqlx::query_as::<_, ProjectAccessDbRow>(
            r#"
            SELECT id, name, current_revision, created_at, updated_at, 'owner'::text AS role
            FROM kshift.project
            ORDER BY name, id
            "#,
        )
        .fetch_all(pool)
        .await
        .map_err(|error| database_error(error, "list all projects"))?
    } else {
        sqlx::query_as::<_, ProjectAccessDbRow>(
            r#"
            SELECT p.id, p.name, p.current_revision, p.created_at, p.updated_at, pm.role
            FROM kshift.project p
            JOIN kshift.project_member pm ON pm.project_id = p.id
            WHERE pm.user_id = $1
            ORDER BY p.name, p.id
            "#,
        )
        .bind(actor.id)
        .fetch_all(pool)
        .await
        .map_err(|error| database_error(error, "list authorized projects"))?
    };

    rows.into_iter()
        .map(|row| {
            let role = role_from_db(&row.role)?;
            Ok((row.project.try_into_domain()?, role))
        })
        .collect()
}

async fn load_authorized_project(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    project_id: Uuid,
    for_update: bool,
) -> Result<ProjectAccessRow, ApiError> {
    if actor.is_admin {
        let sql = if for_update {
            r#"
            SELECT id, name, current_revision, created_at, updated_at
            FROM kshift.project
            WHERE id = $1
            FOR UPDATE
            "#
        } else {
            r#"
            SELECT id, name, current_revision, created_at, updated_at
            FROM kshift.project
            WHERE id = $1
            "#
        };
        let row = sqlx::query_as::<_, ProjectRow>(sql)
            .bind(project_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|error| database_error(error, "load project"))?
            .ok_or_else(|| ApiError::NotFound("project not found".to_owned()))?;
        return Ok(ProjectAccessRow {
            project: row,
            role: ProjectRole::Owner,
        });
    }

    let sql = if for_update {
        r#"
        SELECT p.id, p.name, p.current_revision, p.created_at, p.updated_at, pm.role
        FROM kshift.project p
        JOIN kshift.project_member pm ON pm.project_id = p.id
        WHERE p.id = $1 AND pm.user_id = $2
        FOR UPDATE OF p
        "#
    } else {
        r#"
        SELECT p.id, p.name, p.current_revision, p.created_at, p.updated_at, pm.role
        FROM kshift.project p
        JOIN kshift.project_member pm ON pm.project_id = p.id
        WHERE p.id = $1 AND pm.user_id = $2
        "#
    };
    let row = sqlx::query_as::<_, ProjectAccessDbRow>(sql)
        .bind(project_id)
        .bind(actor.id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|error| database_error(error, "authorize project"))?
        .ok_or(ApiError::PermissionDenied)?;
    Ok(ProjectAccessRow {
        project: row.project,
        role: role_from_db(&row.role)?,
    })
}

async fn lock_project_for_write(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    project_id: Uuid,
    expected_revision: Option<u64>,
) -> Result<ProjectRow, ApiError> {
    let access = load_authorized_project(tx, actor, project_id, true).await?;
    let current_revision = access.project.current_revision_u64()?;
    if let Some(expected_revision) = expected_revision {
        check_expected_revision(current_revision, expected_revision)?;
    }
    Ok(access.project)
}

async fn project_role_for_actor(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    project_id: Uuid,
) -> Result<ProjectRole, ApiError> {
    Ok(load_authorized_project(tx, actor, project_id, false)
        .await?
        .role)
}

async fn require_write_role(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    project_id: Uuid,
) -> Result<(), ApiError> {
    if project_role_for_actor(tx, actor, project_id)
        .await?
        .can_write()
    {
        Ok(())
    } else {
        Err(ApiError::PermissionDenied)
    }
}

fn check_expected_revision(current: u64, expected: u64) -> Result<(), ApiError> {
    if current == expected {
        Ok(())
    } else {
        Err(ApiError::Conflict {
            current_revision: Some(current),
            entity_id: None,
            current_entity_version: None,
        })
    }
}

async fn lock_task(
    tx: &mut Transaction<'_, Postgres>,
    project_id: Uuid,
    task_id: Uuid,
    current_revision: u64,
) -> Result<TaskRow, ApiError> {
    sqlx::query_as::<_, TaskRow>(
        r#"
        SELECT id, project_id, title, description, status, priority, assignee_id,
               due_date, version, created_by, updated_by, created_at, updated_at
        FROM kshift.task
        WHERE id = $1 AND project_id = $2 AND deleted_at IS NULL
        FOR UPDATE
        "#,
    )
    .bind(task_id)
    .bind(project_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|error| database_error(error, "lock task"))?
    .ok_or(ApiError::Conflict {
        current_revision: Some(current_revision),
        entity_id: Some(task_id),
        current_entity_version: None,
    })
}

async fn require_active_user(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
) -> Result<(), ApiError> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM kshift.app_user WHERE id = $1 AND is_active = true)",
    )
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await
    .map_err(|error| database_error(error, "validate assignee"))?;
    if exists {
        Ok(())
    } else {
        Err(ApiError::InvalidArgument(
            "assignee is inactive or not found".to_owned(),
        ))
    }
}

async fn fetch_event_page(
    pool: &PgPool,
    actor: &AuthenticatedUser,
    project_id: Uuid,
    since_revision: u64,
    previous_current_revision: u64,
    batch_size: i64,
) -> Result<EventPage, ApiError> {
    let mut tx = pool
        .begin()
        .await
        .map_err(|error| database_error(error, "begin event stream query"))?;
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        .execute(&mut *tx)
        .await
        .map_err(|error| database_error(error, "configure event stream query"))?;
    let access = load_authorized_project(&mut tx, actor, project_id, false).await?;
    let current_revision = access.project.current_revision_u64()?;
    if since_revision > current_revision {
        tx.rollback()
            .await
            .map_err(|error| database_error(error, "finish event stream query"))?;
        return Ok(EventPage {
            current_revision,
            events: Vec::new(),
            reset: Some(v1::ResetRequired {
                current_revision,
                minimum_retained_revision: current_revision,
                reason: v1::ResetReason::AheadOfServer as i32,
            }),
        });
    }

    let minimum_revision = sqlx::query_scalar::<_, Option<i64>>(
        "SELECT min(revision) FROM kshift.change_event WHERE project_id = $1 AND expires_at > now()",
    )
    .bind(project_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|error| database_error(error, "read outbox retention boundary"))?
    .and_then(|value| u64::try_from(value).ok());

    if since_revision < current_revision {
        let Some(minimum_revision) = minimum_revision else {
            tx.rollback()
                .await
                .map_err(|error| database_error(error, "finish empty event stream query"))?;
            return Ok(EventPage {
                current_revision,
                events: Vec::new(),
                reset: Some(v1::ResetRequired {
                    current_revision,
                    minimum_retained_revision: current_revision,
                    reason: v1::ResetReason::CorruptStream as i32,
                }),
            });
        };
        if since_revision < minimum_revision.saturating_sub(1) {
            tx.rollback()
                .await
                .map_err(|error| database_error(error, "finish retained event stream query"))?;
            return Ok(EventPage {
                current_revision,
                events: Vec::new(),
                reset: Some(v1::ResetRequired {
                    current_revision,
                    minimum_retained_revision: minimum_revision,
                    reason: v1::ResetReason::RetentionGap as i32,
                }),
            });
        }
    }

    let rows = sqlx::query_as::<_, EventRow>(
        r#"
        SELECT revision, schema_version, payload
        FROM kshift.change_event
        WHERE project_id = $1 AND revision > $2 AND expires_at > now()
        ORDER BY revision
        LIMIT $3
        "#,
    )
    .bind(project_id)
    .bind(to_i64(since_revision, "since revision")?)
    .bind(batch_size)
    .fetch_all(&mut *tx)
    .await
    .map_err(|error| database_error(error, "read outbox events"))?;

    tx.commit()
        .await
        .map_err(|error| database_error(error, "commit event stream query"))?;

    if rows.is_empty()
        && current_revision != previous_current_revision
        && current_revision > since_revision
    {
        return Ok(EventPage {
            current_revision,
            events: Vec::new(),
            reset: Some(v1::ResetRequired {
                current_revision,
                minimum_retained_revision: minimum_revision.unwrap_or(current_revision),
                reason: v1::ResetReason::CorruptStream as i32,
            }),
        });
    }

    let mut expected_revision = since_revision.checked_add(1).ok_or(ApiError::Internal)?;
    let mut events = Vec::with_capacity(rows.len());
    for row in rows {
        let revision = u64::try_from(row.revision).map_err(|_| ApiError::Internal)?;
        if revision != expected_revision {
            return Ok(EventPage {
                current_revision,
                events: Vec::new(),
                reset: Some(v1::ResetRequired {
                    current_revision,
                    minimum_retained_revision: revision,
                    reason: v1::ResetReason::CorruptStream as i32,
                }),
            });
        }
        if row.schema_version != SCHEMA_VERSION as i32 {
            return Ok(EventPage {
                current_revision,
                events: Vec::new(),
                reset: Some(v1::ResetRequired {
                    current_revision,
                    minimum_retained_revision: minimum_revision.unwrap_or(revision),
                    reason: v1::ResetReason::SchemaMismatch as i32,
                }),
            });
        }
        let protobuf = v1::ProjectChangeEvent::decode(row.payload.as_slice())
            .map_err(|_| ApiError::FailedPrecondition("stored event is invalid".to_owned()))?;
        let event = collapse_change_event(protobuf, project_id)?;
        if event.revision != revision || event.schema_version != SCHEMA_VERSION {
            return Ok(EventPage {
                current_revision,
                events: Vec::new(),
                reset: Some(v1::ResetRequired {
                    current_revision,
                    minimum_retained_revision: minimum_revision.unwrap_or(revision),
                    reason: v1::ResetReason::CorruptStream as i32,
                }),
            });
        }
        events.push(event);
        expected_revision = expected_revision.checked_add(1).ok_or(ApiError::Internal)?;
    }

    Ok(EventPage {
        current_revision,
        events,
        reset: None,
    })
}

fn parse_uuid(value: &str, field: &str) -> Result<Uuid, ApiError> {
    Uuid::parse_str(value).map_err(|_| ApiError::InvalidArgument(format!("{field} must be a UUID")))
}

fn role_to_db(role: ProjectRole) -> &'static str {
    match role {
        ProjectRole::Viewer => "viewer",
        ProjectRole::Editor => "editor",
        ProjectRole::Owner => "owner",
    }
}

fn role_from_db(value: &str) -> Result<ProjectRole, ApiError> {
    match value {
        "viewer" => Ok(ProjectRole::Viewer),
        "editor" => Ok(ProjectRole::Editor),
        "owner" => Ok(ProjectRole::Owner),
        _ => Err(ApiError::Internal),
    }
}

fn status_to_db(status: TaskStatus) -> &'static str {
    match status {
        TaskStatus::Todo => "todo",
        TaskStatus::InProgress => "in_progress",
        TaskStatus::Blocked => "blocked",
        TaskStatus::Done => "done",
    }
}

fn status_from_db(value: &str) -> Result<TaskStatus, ApiError> {
    match value {
        "todo" => Ok(TaskStatus::Todo),
        "in_progress" => Ok(TaskStatus::InProgress),
        "blocked" => Ok(TaskStatus::Blocked),
        "done" => Ok(TaskStatus::Done),
        _ => Err(ApiError::Internal),
    }
}

fn priority_to_db(priority: TaskPriority) -> i16 {
    match priority {
        TaskPriority::Low => 1,
        TaskPriority::Medium => 2,
        TaskPriority::High => 3,
        TaskPriority::Urgent => 4,
    }
}

fn priority_from_db(value: i16) -> Result<TaskPriority, ApiError> {
    match value {
        1 => Ok(TaskPriority::Low),
        2 => Ok(TaskPriority::Medium),
        3 => Ok(TaskPriority::High),
        4 => Ok(TaskPriority::Urgent),
        _ => Err(ApiError::Internal),
    }
}

fn to_i64(value: u64, field: &str) -> Result<i64, ApiError> {
    i64::try_from(value).map_err(|_| {
        tracing::error!(field, value, "integer value exceeds PostgreSQL bigint");
        ApiError::Internal
    })
}

fn database_error(error: sqlx::Error, operation: &'static str) -> ApiError {
    tracing::error!(operation, error = %error, "database operation failed");
    ApiError::Internal
}

fn command_database_error(error: sqlx::Error, operation: &'static str) -> ApiError {
    if let sqlx::Error::Database(database) = &error {
        match database.code().as_deref() {
            Some("23505") => {
                return ApiError::AlreadyExists("entity already exists".to_owned());
            }
            Some("23503") | Some("23514") | Some("22001") => {
                return ApiError::InvalidArgument("command violates a data constraint".to_owned());
            }
            _ => {}
        }
    }
    database_error(error, operation)
}

fn prost_types_timestamp(value: DateTime<Utc>) -> prost_types::Timestamp {
    prost_types::Timestamp {
        seconds: value.timestamp(),
        nanos: value.timestamp_subsec_nanos() as i32,
    }
}

#[derive(sqlx::FromRow)]
struct CommandResultRow {
    project_id: Uuid,
    actor_id: Uuid,
    request_digest: Vec<u8>,
    response_payload: Vec<u8>,
}

#[derive(sqlx::FromRow)]
struct UserNameRow {
    display_name: String,
}

#[derive(Clone, sqlx::FromRow)]
struct ProjectRow {
    id: Uuid,
    name: String,
    current_revision: i64,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

#[derive(sqlx::FromRow)]
struct ProjectAccessDbRow {
    #[sqlx(flatten)]
    project: ProjectRow,
    role: String,
}

struct ProjectAccessRow {
    project: ProjectRow,
    role: ProjectRole,
}

#[derive(sqlx::FromRow)]
struct MemberRow {
    user_id: Uuid,
    display_name: String,
    role: String,
}

impl TryFrom<MemberRow> for ProjectMember {
    type Error = ApiError;

    fn try_from(value: MemberRow) -> Result<Self, Self::Error> {
        Ok(Self {
            user_id: value.user_id,
            display_name: value.display_name,
            role: role_from_db(&value.role)?,
        })
    }
}

#[derive(Clone, sqlx::FromRow)]
struct TaskRow {
    id: Uuid,
    project_id: Uuid,
    title: String,
    description: String,
    status: String,
    priority: i16,
    assignee_id: Option<Uuid>,
    due_date: Option<NaiveDate>,
    version: i64,
    created_by: Uuid,
    updated_by: Uuid,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl TryFrom<TaskRow> for Task {
    type Error = ApiError;

    fn try_from(value: TaskRow) -> Result<Self, Self::Error> {
        Ok(Self {
            id: value.id,
            project_id: value.project_id,
            title: value.title,
            description: value.description,
            status: status_from_db(&value.status)?,
            priority: priority_from_db(value.priority)?,
            assignee_id: value.assignee_id,
            due_date: value.due_date,
            version: u64::try_from(value.version).map_err(|_| ApiError::Internal)?,
            created_by: value.created_by,
            updated_by: value.updated_by,
            created_at: value.created_at,
            updated_at: value.updated_at,
        })
    }
}

impl ProjectRow {
    fn current_revision_u64(&self) -> Result<u64, ApiError> {
        u64::try_from(self.current_revision).map_err(|_| ApiError::Internal)
    }

    fn try_into_domain(self) -> Result<domain::Project, ApiError> {
        Ok(domain::Project {
            id: self.id,
            name: self.name,
            current_revision: u64::try_from(self.current_revision)
                .map_err(|_| ApiError::Internal)?,
            created_at: self.created_at,
            updated_at: self.updated_at,
        })
    }
}

impl ProjectAccessRow {
    fn try_into_domain(self) -> Result<domain::Project, ApiError> {
        let id = self.project.id;
        let mut project = self.project.try_into_domain()?;
        project.id = id;
        Ok(project)
    }
}

#[derive(sqlx::FromRow)]
struct EventRow {
    revision: i64,
    schema_version: i32,
    payload: Vec<u8>,
}

struct EventPage {
    current_revision: u64,
    events: Vec<ChangeEvent>,
    reset: Option<v1::ResetRequired>,
}
