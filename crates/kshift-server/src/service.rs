use std::{collections::HashMap, pin::Pin, sync::Arc, time::Duration};

use chrono::{DateTime, NaiveDate, Utc};
use contract::{
    change_event_to_proto, collapse_change_event, parse_execute_command, project_snapshot_to_proto,
    project_to_proto, reset_reason_to_string, v1, ApiError, ParsedCommand,
};
use domain::{
    Change, ChangeEvent, Command, ProjectMember, ProjectRole, ProjectSnapshot, ResetReason, Task,
    TaskPatch, TaskPriority, TaskStatus, SCHEMA_VERSION,
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

        let access = load_authorized_project(&mut tx, actor, project_id, false).await?;
        let members = load_project_members(&mut tx, project_id).await?;
        let tasks = load_project_tasks(&mut tx, project_id).await?;
        tx.commit()
            .await
            .map_err(|error| database_error(error, "commit snapshot transaction"))?;

        Ok(ProjectSnapshot {
            project: access.project.try_into_domain()?,
            members,
            tasks,
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

        let retention_days = self.inner.settings.retention_days;
        let event = match &parsed.envelope.command {
            Command::CreateProject { name, time_zone } => {
                create_project(&mut tx, actor, parsed, name, time_zone, retention_days).await?
            }
            Command::AddProjectMember { user_id, role } => {
                add_project_member(
                    &mut tx,
                    actor,
                    parsed,
                    *user_id,
                    *role,
                    request_id,
                    retention_days,
                )
                .await?
            }
            Command::CreateTask {
                task_id,
                title,
                description_markdown,
                status,
                priority,
                assignee_ids,
                planned_on,
                starts_on,
                due_on,
                tags,
                parent_task_id,
                dependency_task_ids,
            } => {
                create_task(
                    &mut tx,
                    actor,
                    parsed,
                    TaskDraft {
                        task_id: *task_id,
                        title,
                        description_markdown,
                        status: *status,
                        priority: *priority,
                        assignee_ids,
                        planned_on: *planned_on,
                        starts_on: *starts_on,
                        due_on: *due_on,
                        tags,
                        parent_task_id: *parent_task_id,
                        dependency_task_ids,
                    },
                    request_id,
                    retention_days,
                )
                .await?
            }
            Command::UpdateTask {
                task_id,
                expected_entity_version,
                patch,
            } => {
                update_task(
                    &mut tx,
                    actor,
                    parsed,
                    *task_id,
                    *expected_entity_version,
                    patch,
                    request_id,
                    retention_days,
                )
                .await?
            }
            Command::DeleteTask {
                task_id,
                expected_entity_version,
            } => {
                delete_task(
                    &mut tx,
                    actor,
                    parsed,
                    *task_id,
                    *expected_entity_version,
                    request_id,
                    retention_days,
                )
                .await?
            }
            Command::BatchUpdateTasks { mutations } => {
                batch_update_tasks(
                    &mut tx,
                    actor,
                    parsed,
                    mutations,
                    request_id,
                    retention_days,
                )
                .await?
            }
        };

        let response = command_response(&event);
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
                        payload: Some(v1::watch_project_changes_response::Payload::Event(
                            change_event_to_proto(&event),
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
                                project_revision: current_revision,
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
        let span = tracing::info_span!("grpc.get_project_snapshot", request_id = %request_id);
        self.get_snapshot_inner(request, request_id)
            .instrument(span)
            .await
            .map(Response::new)
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
            .map(Response::new)
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
        let projects = tokio::time::timeout(
            self.inner.settings.timeouts.unary_request,
            load_visible_projects(&self.inner.pool, &actor),
        )
        .await
        .map_err(|_| ApiError::DeadlineExceeded)??;
        tracing::info!(
            request_id = %request_id,
            user_id = %actor.id,
            project_count = projects.len(),
            "project list completed"
        );
        Ok(v1::ListProjectsResponse {
            projects: projects.iter().map(project_to_proto).collect(),
        })
    }

    async fn get_snapshot_inner(
        &self,
        request: Request<v1::GetProjectSnapshotRequest>,
        request_id: Uuid,
    ) -> Result<v1::GetProjectSnapshotResponse, ApiError> {
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
        Ok(project_snapshot_to_proto(&result))
    }

    async fn execute_command_inner(
        &self,
        request: Request<v1::ExecuteCommandRequest>,
        request_id: Uuid,
    ) -> Result<v1::ExecuteCommandResponse, ApiError> {
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
            "command completed"
        );
        Ok(response)
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
        let access = load_authorized_project(&mut tx, actor, project_id, false).await?;
        let role = access.role;
        tx.rollback()
            .await
            .map_err(|error| database_error(error, "finish authorization transaction"))?;
        Ok(role)
    }
}

struct TaskDraft<'a> {
    task_id: Uuid,
    title: &'a str,
    description_markdown: &'a str,
    status: TaskStatus,
    priority: TaskPriority,
    assignee_ids: &'a [Uuid],
    planned_on: NaiveDate,
    starts_on: Option<NaiveDate>,
    due_on: Option<NaiveDate>,
    tags: &'a [String],
    parent_task_id: Option<Uuid>,
    dependency_task_ids: &'a [Uuid],
}

async fn create_project(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    name: &str,
    time_zone: &str,
    retention_days: i32,
) -> Result<ChangeEvent, ApiError> {
    if !actor.is_admin {
        return Err(ApiError::PermissionDenied);
    }
    let now = Utc::now();
    let project_id = parsed.envelope.project_id;
    sqlx::query(
        r#"
        INSERT INTO kshift.project (
            id, name, time_zone, current_revision, created_by, created_at, updated_at
        )
        VALUES ($1, $2, $3, 1, $4, $5, $5)
        "#,
    )
    .bind(project_id)
    .bind(name)
    .bind(time_zone)
    .bind(actor.id)
    .bind(now)
    .execute(&mut **tx)
    .await
    .map_err(|error| command_database_error(error, "create project"))?;

    sqlx::query(
        r#"
        INSERT INTO kshift.project_member (project_id, user_id, role, created_at, updated_at)
        VALUES ($1, $2, 'admin', $3, $3)
        "#,
    )
    .bind(project_id)
    .bind(actor.id)
    .bind(now)
    .execute(&mut **tx)
    .await
    .map_err(|error| command_database_error(error, "create project owner"))?;

    let project = domain::Project {
        id: project_id,
        name: name.to_owned(),
        time_zone: time_zone.to_owned(),
        current_revision: 1,
        created_at: now,
        updated_at: now,
    };
    let event = ChangeEvent {
        project_id,
        revision: 1,
        schema_version: SCHEMA_VERSION,
        command_id: parsed.envelope.command_id,
        occurred_at: now,
        changes: vec![Change::ProjectUpserted {
            project: project.clone(),
        }],
    };
    insert_event(tx, &event, retention_days).await?;
    insert_audit(
        tx,
        actor,
        parsed,
        "project",
        project_id,
        None,
        Some(serde_json::to_value(&project).map_err(|_| ApiError::Internal)?),
        now,
    )
    .await?;
    Ok(event)
}

async fn add_project_member(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    user_id: Uuid,
    role: ProjectRole,
    request_id: Uuid,
    retention_days: i32,
) -> Result<ChangeEvent, ApiError> {
    let project_id = parsed.envelope.project_id;
    let project =
        lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision).await?;
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
    .ok_or_else(|| ApiError::InvalidArgument("member user is inactive or not found".to_owned()))?;

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
    let event = ChangeEvent {
        project_id,
        revision,
        schema_version: SCHEMA_VERSION,
        command_id: parsed.envelope.command_id,
        occurred_at: now,
        changes: vec![Change::ProjectMemberUpserted {
            member: member.clone(),
        }],
    };
    insert_event(tx, &event, retention_days).await?;
    insert_audit(
        tx,
        actor,
        parsed,
        "project_member",
        user_id,
        previous_role.map(|role| serde_json::json!({ "role": role })),
        Some(serde_json::to_value(&member).map_err(|_| ApiError::Internal)?),
        now,
    )
    .await?;
    tracing::info!(
        request_id = %request_id,
        project_id = %project_id,
        revision,
        member_id = %user_id,
        "project member upserted"
    );
    Ok(event)
}

async fn create_task(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    draft: TaskDraft<'_>,
    request_id: Uuid,
    retention_days: i32,
) -> Result<ChangeEvent, ApiError> {
    let project_id = parsed.envelope.project_id;
    let project =
        lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision).await?;
    let current_revision = project.current_revision_u64()?;
    require_write_role(tx, actor, project_id).await?;
    let now = Utc::now();
    let task = apply_create_task(tx, actor, project_id, draft, now).await?;
    let revision = bump_revision(tx, project_id, current_revision, now).await?;
    let event = ChangeEvent {
        project_id,
        revision,
        schema_version: SCHEMA_VERSION,
        command_id: parsed.envelope.command_id,
        occurred_at: now,
        changes: vec![Change::TaskCreated { task: task.clone() }],
    };
    insert_event(tx, &event, retention_days).await?;
    insert_audit(
        tx,
        actor,
        parsed,
        "task",
        task.id,
        None,
        Some(serde_json::to_value(&task).map_err(|_| ApiError::Internal)?),
        now,
    )
    .await?;
    tracing::info!(
        request_id = %request_id,
        project_id = %project_id,
        revision,
        entity_id = %task.id,
        "task created"
    );
    Ok(event)
}

async fn apply_create_task(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    project_id: Uuid,
    draft: TaskDraft<'_>,
    now: DateTime<Utc>,
) -> Result<Task, ApiError> {
    validate_task_links(
        tx,
        project_id,
        draft.task_id,
        draft.parent_task_id,
        draft.dependency_task_ids,
    )
    .await?;
    validate_assignees(tx, draft.assignee_ids).await?;

    sqlx::query(
        r#"
        INSERT INTO kshift.task (
            id, project_id, title, description_markdown, status, priority,
            planned_on, starts_on, due_on, tags, parent_task_id, version,
            created_by, updated_by, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 1, $12, $12, $13, $13)
        "#,
    )
    .bind(draft.task_id)
    .bind(project_id)
    .bind(draft.title)
    .bind(draft.description_markdown)
    .bind(status_to_db(draft.status))
    .bind(priority_to_db(draft.priority))
    .bind(draft.planned_on)
    .bind(draft.starts_on)
    .bind(draft.due_on)
    .bind(draft.tags)
    .bind(draft.parent_task_id)
    .bind(actor.id)
    .bind(now)
    .execute(&mut **tx)
    .await
    .map_err(|error| command_database_error(error, "create task"))?;
    replace_task_relations(
        tx,
        draft.task_id,
        draft.assignee_ids,
        draft.dependency_task_ids,
    )
    .await?;

    Ok(Task {
        id: draft.task_id,
        project_id,
        title: draft.title.to_owned(),
        description_markdown: draft.description_markdown.to_owned(),
        status: draft.status,
        priority: draft.priority,
        assignee_ids: draft.assignee_ids.to_vec(),
        planned_on: draft.planned_on,
        starts_on: draft.starts_on,
        due_on: draft.due_on,
        tags: draft.tags.to_vec(),
        parent_task_id: draft.parent_task_id,
        dependency_task_ids: draft.dependency_task_ids.to_vec(),
        version: 1,
        created_by: actor.id,
        updated_by: actor.id,
        created_at: now,
        updated_at: now,
    })
}

#[allow(clippy::too_many_arguments)]
async fn update_task(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    task_id: Uuid,
    expected_entity_version: u64,
    patch: &TaskPatch,
    request_id: Uuid,
    retention_days: i32,
) -> Result<ChangeEvent, ApiError> {
    let project_id = parsed.envelope.project_id;
    let project =
        lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision).await?;
    let current_revision = project.current_revision_u64()?;
    require_write_role(tx, actor, project_id).await?;
    let (existing, updated) = apply_update_task(
        tx,
        actor,
        project_id,
        current_revision,
        task_id,
        expected_entity_version,
        patch,
    )
    .await?;
    let revision = bump_revision(tx, project_id, current_revision, updated.updated_at).await?;
    let event = ChangeEvent {
        project_id,
        revision,
        schema_version: SCHEMA_VERSION,
        command_id: parsed.envelope.command_id,
        occurred_at: updated.updated_at,
        changes: vec![Change::TaskUpdated {
            task: updated.clone(),
        }],
    };
    insert_event(tx, &event, retention_days).await?;
    insert_audit(
        tx,
        actor,
        parsed,
        "task",
        task_id,
        Some(serde_json::to_value(&existing).map_err(|_| ApiError::Internal)?),
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
    Ok(event)
}

async fn apply_update_task(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    project_id: Uuid,
    current_revision: u64,
    task_id: Uuid,
    expected_entity_version: u64,
    patch: &TaskPatch,
) -> Result<(Task, Task), ApiError> {
    let existing = lock_task(tx, project_id, task_id, current_revision).await?;
    if existing.version != expected_entity_version {
        return Err(ApiError::Conflict {
            current_revision: Some(current_revision),
            entity_id: Some(task_id),
            current_entity_version: Some(existing.version),
        });
    }
    let updated = domain::update_task(&existing, patch, actor.id).map_err(ApiError::from)?;
    validate_task_links(
        tx,
        project_id,
        task_id,
        updated.parent_task_id,
        &updated.dependency_task_ids,
    )
    .await?;
    validate_assignees(tx, &updated.assignee_ids).await?;

    sqlx::query(
        r#"
        UPDATE kshift.task SET
            title = $3,
            description_markdown = $4,
            status = $5,
            priority = $6,
            planned_on = $7,
            starts_on = $8,
            due_on = $9,
            tags = $10,
            parent_task_id = $11,
            version = $12,
            updated_by = $13,
            updated_at = $14
        WHERE id = $1 AND project_id = $2 AND deleted_at IS NULL
        "#,
    )
    .bind(task_id)
    .bind(project_id)
    .bind(&updated.title)
    .bind(&updated.description_markdown)
    .bind(status_to_db(updated.status))
    .bind(priority_to_db(updated.priority))
    .bind(updated.planned_on)
    .bind(updated.starts_on)
    .bind(updated.due_on)
    .bind(&updated.tags)
    .bind(updated.parent_task_id)
    .bind(to_i64(updated.version, "task version")?)
    .bind(actor.id)
    .bind(updated.updated_at)
    .execute(&mut **tx)
    .await
    .map_err(|error| command_database_error(error, "update task"))?;
    replace_task_relations(
        tx,
        task_id,
        &updated.assignee_ids,
        &updated.dependency_task_ids,
    )
    .await?;
    Ok((existing, updated))
}

async fn delete_task(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    task_id: Uuid,
    expected_entity_version: u64,
    request_id: Uuid,
    retention_days: i32,
) -> Result<ChangeEvent, ApiError> {
    let project_id = parsed.envelope.project_id;
    let project =
        lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision).await?;
    let current_revision = project.current_revision_u64()?;
    require_write_role(tx, actor, project_id).await?;
    let now = Utc::now();
    let (existing, deleted_version) = apply_delete_task(
        tx,
        actor,
        project_id,
        current_revision,
        task_id,
        expected_entity_version,
        now,
    )
    .await?;
    let revision = bump_revision(tx, project_id, current_revision, now).await?;
    let event = ChangeEvent {
        project_id,
        revision,
        schema_version: SCHEMA_VERSION,
        command_id: parsed.envelope.command_id,
        occurred_at: now,
        changes: vec![Change::TaskDeleted { task_id }],
    };
    insert_event(tx, &event, retention_days).await?;
    insert_audit(
        tx,
        actor,
        parsed,
        "task",
        task_id,
        Some(serde_json::to_value(&existing).map_err(|_| ApiError::Internal)?),
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
    Ok(event)
}

async fn batch_update_tasks(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    parsed: &ParsedCommand,
    mutations: &[domain::TaskMutation],
    request_id: Uuid,
    retention_days: i32,
) -> Result<ChangeEvent, ApiError> {
    let project_id = parsed.envelope.project_id;
    let project =
        lock_project_for_write(tx, actor, project_id, parsed.envelope.expected_revision).await?;
    let current_revision = project.current_revision_u64()?;
    require_write_role(tx, actor, project_id).await?;
    let now = Utc::now();
    let mut changes = Vec::with_capacity(mutations.len());

    for mutation in mutations {
        match mutation {
            domain::TaskMutation::CreateTask {
                task_id,
                title,
                description_markdown,
                status,
                priority,
                assignee_ids,
                planned_on,
                starts_on,
                due_on,
                tags,
                parent_task_id,
                dependency_task_ids,
            } => {
                let task = apply_create_task(
                    tx,
                    actor,
                    project_id,
                    TaskDraft {
                        task_id: *task_id,
                        title,
                        description_markdown,
                        status: *status,
                        priority: *priority,
                        assignee_ids,
                        planned_on: *planned_on,
                        starts_on: *starts_on,
                        due_on: *due_on,
                        tags,
                        parent_task_id: *parent_task_id,
                        dependency_task_ids,
                    },
                    now,
                )
                .await?;
                insert_audit(
                    tx,
                    actor,
                    parsed,
                    "task",
                    task.id,
                    None,
                    Some(serde_json::to_value(&task).map_err(|_| ApiError::Internal)?),
                    now,
                )
                .await?;
                changes.push(Change::TaskCreated { task });
            }
            domain::TaskMutation::UpdateTask {
                task_id,
                expected_entity_version,
                patch,
            } => {
                let (existing, updated) = apply_update_task(
                    tx,
                    actor,
                    project_id,
                    current_revision,
                    *task_id,
                    *expected_entity_version,
                    patch,
                )
                .await?;
                insert_audit(
                    tx,
                    actor,
                    parsed,
                    "task",
                    *task_id,
                    Some(serde_json::to_value(&existing).map_err(|_| ApiError::Internal)?),
                    Some(serde_json::to_value(&updated).map_err(|_| ApiError::Internal)?),
                    updated.updated_at,
                )
                .await?;
                changes.push(Change::TaskUpdated { task: updated });
            }
            domain::TaskMutation::DeleteTask {
                task_id,
                expected_entity_version,
            } => {
                let (existing, deleted_version) = apply_delete_task(
                    tx,
                    actor,
                    project_id,
                    current_revision,
                    *task_id,
                    *expected_entity_version,
                    now,
                )
                .await?;
                insert_audit(
                    tx,
                    actor,
                    parsed,
                    "task",
                    *task_id,
                    Some(serde_json::to_value(&existing).map_err(|_| ApiError::Internal)?),
                    Some(serde_json::json!({
                        "id": task_id,
                        "version": deleted_version,
                        "deleted_at": now
                    })),
                    now,
                )
                .await?;
                changes.push(Change::TaskDeleted { task_id: *task_id });
            }
        }
    }

    let revision = bump_revision(tx, project_id, current_revision, now).await?;
    let event = ChangeEvent {
        project_id,
        revision,
        schema_version: SCHEMA_VERSION,
        command_id: parsed.envelope.command_id,
        occurred_at: now,
        changes,
    };
    insert_event(tx, &event, retention_days).await?;
    tracing::info!(
        request_id = %request_id,
        project_id = %project_id,
        revision,
        mutation_count = mutations.len(),
        "task batch updated"
    );
    Ok(event)
}

async fn apply_delete_task(
    tx: &mut Transaction<'_, Postgres>,
    actor: &AuthenticatedUser,
    project_id: Uuid,
    current_revision: u64,
    task_id: Uuid,
    expected_entity_version: u64,
    now: DateTime<Utc>,
) -> Result<(Task, u64), ApiError> {
    let existing = lock_task(tx, project_id, task_id, current_revision).await?;
    if existing.version != expected_entity_version {
        return Err(ApiError::Conflict {
            current_revision: Some(current_revision),
            entity_id: Some(task_id),
            current_entity_version: Some(existing.version),
        });
    }
    let deleted_version = existing.version.checked_add(1).ok_or(ApiError::Internal)?;
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
    Ok((existing, deleted_version))
}

fn command_response(event: &ChangeEvent) -> v1::ExecuteCommandResponse {
    v1::ExecuteCommandResponse {
        result: Some(v1::CommandResult {
            command_id: event.command_id.to_string(),
            project_revision: event.revision,
            event: Some(change_event_to_proto(event)),
        }),
    }
}

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

async fn load_project_members(
    tx: &mut Transaction<'_, Postgres>,
    project_id: Uuid,
) -> Result<Vec<ProjectMember>, ApiError> {
    let rows = sqlx::query_as::<_, MemberRow>(
        r#"
        SELECT pm.user_id, u.display_name, pm.role
        FROM kshift.project_member pm
        JOIN kshift.app_user u ON u.id = pm.user_id
        WHERE pm.project_id = $1
        ORDER BY u.display_name, pm.user_id
        "#,
    )
    .bind(project_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|error| database_error(error, "load project members"))?;
    rows.into_iter().map(TryInto::try_into).collect()
}

async fn load_project_tasks(
    tx: &mut Transaction<'_, Postgres>,
    project_id: Uuid,
) -> Result<Vec<Task>, ApiError> {
    let rows = sqlx::query_as::<_, TaskRow>(
        r#"
        SELECT id, project_id, title, description_markdown, status, priority,
               planned_on, starts_on, due_on, tags, parent_task_id, version,
               created_by, updated_by, created_at, updated_at
        FROM kshift.task
        WHERE project_id = $1 AND deleted_at IS NULL
        ORDER BY planned_on, created_at, id
        "#,
    )
    .bind(project_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|error| database_error(error, "load project tasks"))?;
    let (assignees, dependencies) = load_project_relations(tx, project_id).await?;
    rows.into_iter()
        .map(|row| {
            let task_id = row.id;
            row.into_domain(
                assignees.get(&task_id).cloned().unwrap_or_default(),
                dependencies.get(&task_id).cloned().unwrap_or_default(),
            )
        })
        .collect()
}

async fn load_project_relations(
    tx: &mut Transaction<'_, Postgres>,
    project_id: Uuid,
) -> Result<(HashMap<Uuid, Vec<Uuid>>, HashMap<Uuid, Vec<Uuid>>), ApiError> {
    let assignee_rows = sqlx::query_as::<_, TaskAssigneeRow>(
        r#"
        SELECT ta.task_id, ta.user_id
        FROM kshift.task_assignee ta
        JOIN kshift.task t ON t.id = ta.task_id
        WHERE t.project_id = $1 AND t.deleted_at IS NULL
        ORDER BY ta.task_id, ta.user_id
        "#,
    )
    .bind(project_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|error| database_error(error, "load task assignees"))?;
    let dependency_rows = sqlx::query_as::<_, TaskDependencyRow>(
        r#"
        SELECT td.task_id, td.depends_on_task_id
        FROM kshift.task_dependency td
        JOIN kshift.task t ON t.id = td.task_id
        WHERE t.project_id = $1 AND t.deleted_at IS NULL
        ORDER BY td.task_id, td.depends_on_task_id
        "#,
    )
    .bind(project_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|error| database_error(error, "load task dependencies"))?;

    let mut assignees = HashMap::<Uuid, Vec<Uuid>>::new();
    for row in assignee_rows {
        assignees.entry(row.task_id).or_default().push(row.user_id);
    }
    let mut dependencies = HashMap::<Uuid, Vec<Uuid>>::new();
    for row in dependency_rows {
        dependencies
            .entry(row.task_id)
            .or_default()
            .push(row.depends_on_task_id);
    }
    Ok((assignees, dependencies))
}

async fn lock_task(
    tx: &mut Transaction<'_, Postgres>,
    project_id: Uuid,
    task_id: Uuid,
    current_revision: u64,
) -> Result<Task, ApiError> {
    let row = sqlx::query_as::<_, TaskRow>(
        r#"
        SELECT id, project_id, title, description_markdown, status, priority,
               planned_on, starts_on, due_on, tags, parent_task_id, version,
               created_by, updated_by, created_at, updated_at
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
    })?;

    let assignee_ids = sqlx::query_scalar::<_, Uuid>(
        "SELECT user_id FROM kshift.task_assignee WHERE task_id = $1 ORDER BY user_id",
    )
    .bind(task_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|error| database_error(error, "load task assignees"))?;
    let dependency_task_ids = sqlx::query_scalar::<_, Uuid>(
        "SELECT depends_on_task_id FROM kshift.task_dependency WHERE task_id = $1 ORDER BY depends_on_task_id",
    )
    .bind(task_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|error| database_error(error, "load task dependencies"))?;
    row.into_domain(assignee_ids, dependency_task_ids)
}

async fn replace_task_relations(
    tx: &mut Transaction<'_, Postgres>,
    task_id: Uuid,
    assignee_ids: &[Uuid],
    dependency_task_ids: &[Uuid],
) -> Result<(), ApiError> {
    sqlx::query("DELETE FROM kshift.task_assignee WHERE task_id = $1")
        .bind(task_id)
        .execute(&mut **tx)
        .await
        .map_err(|error| database_error(error, "clear task assignees"))?;
    sqlx::query("DELETE FROM kshift.task_dependency WHERE task_id = $1")
        .bind(task_id)
        .execute(&mut **tx)
        .await
        .map_err(|error| database_error(error, "clear task dependencies"))?;

    for user_id in assignee_ids {
        sqlx::query("INSERT INTO kshift.task_assignee (task_id, user_id) VALUES ($1, $2)")
            .bind(task_id)
            .bind(user_id)
            .execute(&mut **tx)
            .await
            .map_err(|error| command_database_error(error, "insert task assignee"))?;
    }
    for dependency_id in dependency_task_ids {
        sqlx::query(
            "INSERT INTO kshift.task_dependency (task_id, depends_on_task_id) VALUES ($1, $2)",
        )
        .bind(task_id)
        .bind(dependency_id)
        .execute(&mut **tx)
        .await
        .map_err(|error| command_database_error(error, "insert task dependency"))?;
    }
    Ok(())
}

async fn validate_assignees(
    tx: &mut Transaction<'_, Postgres>,
    assignee_ids: &[Uuid],
) -> Result<(), ApiError> {
    if assignee_ids.is_empty() {
        return Ok(());
    }
    let rows = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM kshift.app_user WHERE id = ANY($1) AND is_active = true FOR SHARE",
    )
    .bind(assignee_ids)
    .fetch_all(&mut **tx)
    .await
    .map_err(|error| database_error(error, "validate assignees"))?;
    if rows.len() != assignee_ids.len() {
        return Err(ApiError::InvalidArgument(
            "assignee_ids contains an inactive or unknown user".to_owned(),
        ));
    }
    Ok(())
}

async fn validate_task_links(
    tx: &mut Transaction<'_, Postgres>,
    project_id: Uuid,
    task_id: Uuid,
    parent_task_id: Option<Uuid>,
    dependency_task_ids: &[Uuid],
) -> Result<(), ApiError> {
    if let Some(parent_task_id) = parent_task_id {
        let parent = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT id FROM kshift.task
            WHERE id = $1 AND project_id = $2 AND deleted_at IS NULL
            FOR SHARE
            "#,
        )
        .bind(parent_task_id)
        .bind(project_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|error| database_error(error, "validate parent task"))?;
        if parent.is_none() {
            return Err(ApiError::InvalidArgument(
                "parent_task_id is not an active task in this project".to_owned(),
            ));
        }
    }

    if !dependency_task_ids.is_empty() {
        if dependency_task_ids.contains(&task_id) {
            return Err(ApiError::InvalidArgument(
                "dependency_task_ids must not reference the task itself".to_owned(),
            ));
        }
        let rows = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT id FROM kshift.task
            WHERE project_id = $1 AND deleted_at IS NULL AND id = ANY($2)
            FOR SHARE
            "#,
        )
        .bind(project_id)
        .bind(dependency_task_ids)
        .fetch_all(&mut **tx)
        .await
        .map_err(|error| database_error(error, "validate dependency tasks"))?;
        if rows.len() != dependency_task_ids.len() {
            return Err(ApiError::InvalidArgument(
                "dependency_task_ids contains a missing or unauthorized task".to_owned(),
            ));
        }
    }
    Ok(())
}

async fn load_visible_projects(
    pool: &PgPool,
    actor: &AuthenticatedUser,
) -> Result<Vec<domain::Project>, ApiError> {
    let rows = if actor.is_admin {
        sqlx::query_as::<_, ProjectRow>(
            r#"
            SELECT id, name, time_zone, current_revision, created_at, updated_at
            FROM kshift.project
            ORDER BY name, id
            "#,
        )
        .fetch_all(pool)
        .await
    } else {
        sqlx::query_as::<_, ProjectRow>(
            r#"
            SELECT p.id, p.name, p.time_zone, p.current_revision, p.created_at, p.updated_at
            FROM kshift.project p
            JOIN kshift.project_member pm ON pm.project_id = p.id
            WHERE pm.user_id = $1
            ORDER BY p.name, p.id
            "#,
        )
        .bind(actor.id)
        .fetch_all(pool)
        .await
    }
    .map_err(|error| database_error(error, "list projects"))?;

    rows.into_iter().map(ProjectRow::try_into_domain).collect()
}

struct ProjectAccessRow {
    project: ProjectRow,
    role: ProjectRole,
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
            SELECT id, name, time_zone, current_revision, created_at, updated_at
            FROM kshift.project
            WHERE id = $1
            FOR UPDATE
            "#
        } else {
            r#"
            SELECT id, name, time_zone, current_revision, created_at, updated_at
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
            role: ProjectRole::Admin,
        });
    }

    let sql = if for_update {
        r#"
        SELECT p.id, p.name, p.time_zone, p.current_revision, p.created_at, p.updated_at, pm.role
        FROM kshift.project p
        JOIN kshift.project_member pm ON pm.project_id = p.id
        WHERE p.id = $1 AND pm.user_id = $2
        FOR UPDATE OF p
        "#
    } else {
        r#"
        SELECT p.id, p.name, p.time_zone, p.current_revision, p.created_at, p.updated_at, pm.role
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
            reset: Some(reset_required(
                current_revision,
                current_revision,
                ResetReason::AheadOfServer,
            )),
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
                reset: Some(reset_required(
                    current_revision,
                    current_revision,
                    ResetReason::CorruptStream,
                )),
            });
        };
        if since_revision < minimum_revision.saturating_sub(1) {
            tx.rollback()
                .await
                .map_err(|error| database_error(error, "finish retained event stream query"))?;
            return Ok(EventPage {
                current_revision,
                events: Vec::new(),
                reset: Some(reset_required(
                    current_revision,
                    minimum_revision,
                    ResetReason::RetentionGap,
                )),
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
            reset: Some(reset_required(
                current_revision,
                minimum_revision.unwrap_or(current_revision),
                ResetReason::CorruptStream,
            )),
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
                reset: Some(reset_required(
                    current_revision,
                    revision,
                    ResetReason::CorruptStream,
                )),
            });
        }
        if row.schema_version != SCHEMA_VERSION as i32 {
            return Ok(EventPage {
                current_revision,
                events: Vec::new(),
                reset: Some(reset_required(
                    current_revision,
                    minimum_revision.unwrap_or(revision),
                    ResetReason::SchemaMismatch,
                )),
            });
        }
        let protobuf = v1::ProjectChangeEvent::decode(row.payload.as_slice())
            .map_err(|_| ApiError::FailedPrecondition("stored event is invalid".to_owned()))?;
        let event = collapse_change_event(protobuf, project_id)?;
        if event.revision != revision || event.schema_version != SCHEMA_VERSION {
            return Ok(EventPage {
                current_revision,
                events: Vec::new(),
                reset: Some(reset_required(
                    current_revision,
                    minimum_revision.unwrap_or(revision),
                    ResetReason::CorruptStream,
                )),
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

fn reset_required(
    current_revision: u64,
    minimum_retained_revision: u64,
    reason: ResetReason,
) -> v1::ResetRequired {
    v1::ResetRequired {
        current_revision,
        reason: reset_reason_to_string(reason).to_owned(),
        minimum_retained_revision,
    }
}

fn parse_uuid(value: &str, field: &str) -> Result<Uuid, ApiError> {
    Uuid::parse_str(value).map_err(|_| ApiError::InvalidArgument(format!("{field} must be a UUID")))
}

fn role_to_db(role: ProjectRole) -> &'static str {
    match role {
        ProjectRole::Viewer => "viewer",
        ProjectRole::Editor => "editor",
        ProjectRole::Admin => "admin",
    }
}

fn role_from_db(value: &str) -> Result<ProjectRole, ApiError> {
    match value {
        "viewer" => Ok(ProjectRole::Viewer),
        "editor" => Ok(ProjectRole::Editor),
        "admin" => Ok(ProjectRole::Admin),
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
        TaskPriority::None => 1,
        TaskPriority::Low => 2,
        TaskPriority::Medium => 3,
        TaskPriority::High => 4,
        TaskPriority::Urgent => 5,
    }
}

fn priority_from_db(value: i16) -> Result<TaskPriority, ApiError> {
    match value {
        1 => Ok(TaskPriority::None),
        2 => Ok(TaskPriority::Low),
        3 => Ok(TaskPriority::Medium),
        4 => Ok(TaskPriority::High),
        5 => Ok(TaskPriority::Urgent),
        _ => Err(ApiError::Internal),
    }
}

fn to_i64(value: u64, field: &str) -> Result<i64, ApiError> {
    i64::try_from(value).map_err(|_| {
        tracing::error!(
            field = field,
            value,
            "integer value exceeds PostgreSQL bigint"
        );
        ApiError::Internal
    })
}

fn database_error(error: sqlx::Error, operation: &'static str) -> ApiError {
    tracing::error!(operation = operation, error = %error, "database operation failed");
    ApiError::Internal
}

fn command_database_error(error: sqlx::Error, operation: &'static str) -> ApiError {
    if let sqlx::Error::Database(database) = &error {
        match database.code().as_deref() {
            Some("23505") => {
                return ApiError::AlreadyExists("entity already exists".to_owned());
            }
            Some("23503") | Some("23514") | Some("22001") | Some("22P02") => {
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
    time_zone: String,
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
    description_markdown: String,
    status: String,
    priority: i16,
    planned_on: NaiveDate,
    starts_on: Option<NaiveDate>,
    due_on: Option<NaiveDate>,
    tags: Vec<String>,
    parent_task_id: Option<Uuid>,
    version: i64,
    created_by: Uuid,
    updated_by: Uuid,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl TaskRow {
    fn into_domain(
        self,
        assignee_ids: Vec<Uuid>,
        dependency_task_ids: Vec<Uuid>,
    ) -> Result<Task, ApiError> {
        Ok(Task {
            id: self.id,
            project_id: self.project_id,
            title: self.title,
            description_markdown: self.description_markdown,
            status: status_from_db(&self.status)?,
            priority: priority_from_db(self.priority)?,
            assignee_ids,
            planned_on: self.planned_on,
            starts_on: self.starts_on,
            due_on: self.due_on,
            tags: self.tags,
            parent_task_id: self.parent_task_id,
            dependency_task_ids,
            version: u64::try_from(self.version).map_err(|_| ApiError::Internal)?,
            created_by: self.created_by,
            updated_by: self.updated_by,
            created_at: self.created_at,
            updated_at: self.updated_at,
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
            time_zone: self.time_zone,
            current_revision: u64::try_from(self.current_revision)
                .map_err(|_| ApiError::Internal)?,
            created_at: self.created_at,
            updated_at: self.updated_at,
        })
    }
}

#[derive(sqlx::FromRow)]
struct TaskAssigneeRow {
    task_id: Uuid,
    user_id: Uuid,
}

#[derive(sqlx::FromRow)]
struct TaskDependencyRow {
    task_id: Uuid,
    depends_on_task_id: Uuid,
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
