use std::sync::Arc;
use std::time::{Duration, Instant};

use chrono::{DateTime, NaiveDate, Utc};
use contract::{v1, MAX_UNARY_REQUEST_BYTES};
use domain::{
    ChangeEvent, Command, CommandEnvelope, Maybe, Project, ProjectAuditEntry, ProjectMember,
    ProjectSnapshot, ResetReason, Task, TaskMutation, TaskPatch, TaskPriority, TaskStatus,
};
use prost_types::Timestamp;
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, RwLock};
use tokio_util::sync::CancellationToken;
use tonic::transport::{Certificate, Channel, ClientTlsConfig, Endpoint};
use tonic::Request;
use uuid::Uuid;

use crate::cache::{EventApplyResult, SnapshotCache};
use crate::error::ClientErrorView;
use crate::retry::{jittered_retry_delay, retry_with_deadline};
use crate::{AttachmentCache, AuthToken, ClientConfig, ClientError};

const WATCH_HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(30);
const WATCH_MAX_BACKOFF_EXPONENT: u32 = 5;

/// Project row returned by `ListProjects`.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ProjectSummary {
    /// Project identity.
    pub id: Uuid,
    /// Project display name.
    pub name: String,
    /// IANA time zone.
    pub time_zone: String,
    /// Current project revision.
    pub current_revision: u64,
}

/// Successful command outcome.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CommandOutcome {
    /// Command identity.
    pub command_id: Uuid,
    /// New project revision.
    pub revision: u64,
    /// Single normalized change committed by the command.
    pub event: ChangeEvent,
}

/// Event delivered to a Swift subscription.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ClientEvent {
    /// Fresh snapshot fetched at subscriptions start or after reset.
    Snapshot(ProjectSnapshot),
    /// Consecutive change event.
    Change(ChangeEvent),
    /// Cached state was discarded and a fresh snapshot is required.
    ResetRequired(ResetNotice),
    /// The watch worker will reconnect after a transient failure.
    Reconnecting(ReconnectNotice),
    /// A terminal client error.
    Error(ClientErrorView),
}

/// Reset notification for a project.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ResetNotice {
    /// Project identity.
    pub project_id: Uuid,
    /// Revision known before reset.
    pub current_revision: u64,
    /// Oldest revision retained by the server.
    pub minimum_retained_revision: u64,
    /// Machine-readable reset reason.
    pub reason: String,
}

/// Reconnect notification.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ReconnectNotice {
    /// One-based reconnect attempt.
    pub attempt: u32,
    /// Delay before the reconnect.
    pub retry_in_ms: u64,
}

/// Why a watch worker stopped.
#[derive(Debug)]
pub enum WatchExit {
    /// The caller cancelled the worker.
    Cancelled,
    /// The receiver dropped and no host remains.
    ReceiverClosed,
    /// A non-retryable error ended the worker.
    Terminal(ClientError),
}

/// Rust gRPC client with bounded cache and watch recovery.
pub struct KshiftClient {
    config: Arc<ClientConfig>,
    service: contract::KshiftServiceClient<Channel>,
    token: RwLock<Option<AuthToken>>,
    snapshots: Arc<SnapshotCache>,
    attachments: Arc<AttachmentCache>,
}

impl KshiftClient {
    /// Build a lazy TLS channel. The first RPC establishes the connection.
    pub fn new(config: ClientConfig) -> Result<Self, ClientError> {
        let mut tls = ClientTlsConfig::new().ca_certificate(Certificate::from_pem(config.ca_pem()));
        if let Some(domain) = config.tls_domain() {
            tls = tls.domain_name(domain.to_owned());
        }
        let endpoint = Endpoint::from_shared(config.endpoint().to_owned())
            .map_err(|error| ClientError::InvalidConfig(format!("invalid endpoint: {error}")))?
            .tls_config(tls)
            .map_err(|error| ClientError::InvalidConfig(format!("invalid TLS config: {error}")))?
            .connect_timeout(Duration::from_secs(5))
            .http2_keep_alive_interval(Duration::from_secs(30))
            .keep_alive_timeout(Duration::from_secs(10))
            .tcp_nodelay(true);
        let channel = endpoint.connect_lazy();
        let service = contract::KshiftServiceClient::new(channel)
            .max_decoding_message_size(config.max_response_bytes())
            .max_encoding_message_size(MAX_UNARY_REQUEST_BYTES);
        Ok(Self {
            config: Arc::new(config),
            service,
            token: RwLock::new(None),
            snapshots: Arc::new(SnapshotCache::default()),
            attachments: Arc::new(AttachmentCache::default()),
        })
    }

    /// Replace the bearer token.
    pub async fn set_token(&self, token: AuthToken) {
        *self.token.write().await = Some(token);
    }

    /// Clear the bearer token and all business caches.
    pub async fn clear_token(&self) {
        *self.token.write().await = None;
        self.clear_caches();
    }

    /// Clear normalized snapshots and attachment bytes.
    pub fn clear_caches(&self) {
        self.snapshots.clear_all();
        self.attachments.clear();
    }

    /// Clear one project snapshot after authorization loss.
    pub fn clear_project(&self, project_id: Uuid) {
        self.snapshots.clear_project(project_id);
    }

    /// Read a project from the memory snapshot cache.
    pub fn cached_snapshot(&self, project_id: Uuid) -> Option<ProjectSnapshot> {
        self.snapshots.get(project_id)
    }

    /// Cache one attachment by SHA-256 key.
    pub fn cache_attachment(&self, sha256_hex: &str, bytes: &[u8]) -> Result<(), ClientError> {
        self.attachments.put(sha256_hex, bytes.to_vec())
    }

    /// Read one cached attachment by SHA-256 key.
    pub fn cached_attachment(&self, sha256_hex: &str) -> Option<Vec<u8>> {
        self.attachments.get(sha256_hex)
    }

    /// Clear the attachment cache.
    pub fn clear_attachment_cache(&self) {
        self.attachments.clear();
    }

    /// List the projects visible to the current identity.
    pub async fn list_projects(
        &self,
        deadline: Option<Duration>,
        cancel: &CancellationToken,
    ) -> Result<Vec<ProjectSummary>, ClientError> {
        let token = self.required_token().await?;
        let effective_deadline = self.config.effective_deadline(deadline);
        let deadline_at = Instant::now()
            .checked_add(effective_deadline)
            .ok_or(ClientError::DeadlineExceeded)?;
        let service = self.service.clone();
        let response = retry_with_deadline(
            self.config.retry_policy(),
            deadline_at,
            cancel,
            |remaining| {
                let mut service = service.clone();
                let token = token.clone();
                let request = self.request(v1::ListProjectsRequest {}, remaining, &token);
                async move {
                    service
                        .list_projects(request?)
                        .await
                        .map(|response| response.into_inner())
                        .map_err(ClientError::from)
                }
            },
        )
        .await
        .map_err(|error| normalize_deadline_error(error, deadline_at));

        let response = match response {
            Ok(response) => response,
            Err(error) => {
                self.update_cache_for_error(&error, None).await;
                return Err(error);
            }
        };
        response
            .projects
            .into_iter()
            .map(project_summary_from_proto)
            .collect()
    }

    /// Fetch a fresh snapshot and update the normalized cache.
    pub async fn get_snapshot(
        &self,
        project_id: Uuid,
        deadline: Option<Duration>,
        cancel: &CancellationToken,
    ) -> Result<ProjectSnapshot, ClientError> {
        if project_id.is_nil() {
            return Err(ClientError::InvalidArgument(
                "project_id must not be nil".to_owned(),
            ));
        }
        let token = self.required_token().await?;
        let effective_deadline = self.config.effective_deadline(deadline);
        let deadline_at = Instant::now()
            .checked_add(effective_deadline)
            .ok_or(ClientError::DeadlineExceeded)?;
        let service = self.service.clone();
        let response = retry_with_deadline(
            self.config.retry_policy(),
            deadline_at,
            cancel,
            |remaining| {
                let mut service = service.clone();
                let token = token.clone();
                let request = self.request(
                    v1::GetProjectSnapshotRequest {
                        project_id: project_id.to_string(),
                    },
                    remaining,
                    &token,
                );
                async move {
                    service
                        .get_project_snapshot(request?)
                        .await
                        .map(|response| response.into_inner())
                        .map_err(ClientError::from)
                }
            },
        )
        .await
        .map_err(|error| normalize_deadline_error(error, deadline_at));

        let response = match response {
            Ok(response) => response,
            Err(error) => {
                self.update_cache_for_error(&error, Some(project_id)).await;
                return Err(error);
            }
        };
        let snapshot = project_snapshot_from_proto(response)?;
        if snapshot.project.id != project_id {
            return Err(ClientError::Protocol(
                "snapshot project_id does not match request".to_owned(),
            ));
        }
        if !self.snapshots.put(snapshot.clone()) {
            return Err(ClientError::ResponseTooLarge {
                field: "snapshot",
                actual: serde_json::to_vec(&snapshot)
                    .map(|bytes| bytes.len())
                    .unwrap_or(usize::MAX),
                limit: 128 * 1024 * 1024,
            });
        }
        Ok(snapshot)
    }

    /// Execute one typed, idempotent command.
    pub async fn execute_command(
        &self,
        command: &CommandEnvelope,
        deadline: Option<Duration>,
        cancel: &CancellationToken,
    ) -> Result<CommandOutcome, ClientError> {
        command.validate()?;
        let token = self.required_token().await?;
        let wire_command = command_envelope_to_proto(command)?;
        let effective_deadline = self.config.effective_deadline(deadline);
        let deadline_at = Instant::now()
            .checked_add(effective_deadline)
            .ok_or(ClientError::DeadlineExceeded)?;
        let service = self.service.clone();
        let result = retry_with_deadline(
            self.config.retry_policy(),
            deadline_at,
            cancel,
            |remaining| {
                let mut service = service.clone();
                let token = token.clone();
                let command = wire_command.clone();
                let request = self.request(
                    v1::ExecuteCommandRequest {
                        command: Some(command),
                    },
                    remaining,
                    &token,
                );
                async move {
                    service
                        .execute_command(request?)
                        .await
                        .map(|response| response.into_inner())
                        .map_err(ClientError::from)
                }
            },
        )
        .await
        .map_err(|error| normalize_deadline_error(error, deadline_at));

        let response = match result {
            Ok(response) => response,
            Err(error) => {
                self.update_cache_for_error(&error, Some(command.project_id))
                    .await;
                return Err(error);
            }
        };
        let outcome = command_outcome_from_proto(response)?;
        match self.snapshots.apply_event(&outcome.event) {
            EventApplyResult::Gap { .. } | EventApplyResult::Invalid => {
                self.snapshots.clear_project(command.project_id);
            }
            EventApplyResult::Applied { .. }
            | EventApplyResult::AlreadyApplied
            | EventApplyResult::NotCached
            | EventApplyResult::BudgetExceeded => {}
        }
        Ok(outcome)
    }

    /// Keep a project snapshot synchronized until cancellation.
    pub async fn watch_project(
        &self,
        project_id: Uuid,
        initial_revision: Option<u64>,
        cancel: CancellationToken,
        tx: mpsc::Sender<ClientEvent>,
    ) -> WatchExit {
        if project_id.is_nil() {
            return WatchExit::Terminal(ClientError::InvalidArgument(
                "project_id must not be nil".to_owned(),
            ));
        }

        let mut revision = initial_revision;
        let mut reconnect_attempt = 0_u32;
        loop {
            if cancel.is_cancelled() {
                return WatchExit::Cancelled;
            }
            if revision.is_none() {
                match self.get_snapshot(project_id, None, &cancel).await {
                    Ok(snapshot) => {
                        revision = Some(snapshot.project.current_revision);
                        if tx.send(ClientEvent::Snapshot(snapshot)).await.is_err() {
                            return WatchExit::ReceiverClosed;
                        }
                        reconnect_attempt = 0;
                    }
                    Err(ClientError::Cancelled) => return WatchExit::Cancelled,
                    Err(error) if error.retryable() => {
                        reconnect_attempt = reconnect_attempt.saturating_add(1);
                        let delay = watch_delay(reconnect_attempt);
                        if send_reconnecting(&tx, reconnect_attempt, delay)
                            .await
                            .is_err()
                        {
                            return WatchExit::ReceiverClosed;
                        }
                        if !sleep_or_cancel(delay, &cancel).await {
                            return WatchExit::Cancelled;
                        }
                        continue;
                    }
                    Err(error) => {
                        let _ = tx.send(ClientEvent::Error(error.view())).await;
                        return WatchExit::Terminal(error);
                    }
                }
            }

            let since_revision = revision.unwrap_or(0);
            match self
                .watch_stream_once(project_id, since_revision, &cancel, &tx)
                .await
            {
                Ok(next_revision) => {
                    revision = Some(next_revision);
                    reconnect_attempt = 0;
                    let delay = watch_delay(1);
                    if send_reconnecting(&tx, 1, delay).await.is_err() {
                        return WatchExit::ReceiverClosed;
                    }
                    if !sleep_or_cancel(delay, &cancel).await {
                        return WatchExit::Cancelled;
                    }
                }
                Err(WatchFlowError::ReceiverClosed) => return WatchExit::ReceiverClosed,
                Err(WatchFlowError::Client(ClientError::Cancelled)) => {
                    return WatchExit::Cancelled;
                }
                Err(WatchFlowError::Client(ClientError::ResetRequired {
                    current_revision,
                    minimum_retained_revision,
                    reason,
                })) => {
                    self.snapshots.clear_project(project_id);
                    let notice = ResetNotice {
                        project_id,
                        current_revision,
                        minimum_retained_revision,
                        reason: reset_reason_name(reason).to_owned(),
                    };
                    if tx.send(ClientEvent::ResetRequired(notice)).await.is_err() {
                        return WatchExit::ReceiverClosed;
                    }
                    revision = None;
                    reconnect_attempt = 0;
                }
                Err(WatchFlowError::Client(error)) if error.retryable() => {
                    reconnect_attempt = reconnect_attempt.saturating_add(1);
                    let delay = watch_delay(reconnect_attempt);
                    if send_reconnecting(&tx, reconnect_attempt, delay)
                        .await
                        .is_err()
                    {
                        return WatchExit::ReceiverClosed;
                    }
                    if !sleep_or_cancel(delay, &cancel).await {
                        return WatchExit::Cancelled;
                    }
                }
                Err(WatchFlowError::Client(error)) => {
                    let _ = tx.send(ClientEvent::Error(error.view())).await;
                    return WatchExit::Terminal(error);
                }
            }
        }
    }

    async fn watch_stream_once(
        &self,
        project_id: Uuid,
        since_revision: u64,
        cancel: &CancellationToken,
        tx: &mpsc::Sender<ClientEvent>,
    ) -> Result<u64, WatchFlowError> {
        let token = self
            .required_token()
            .await
            .map_err(WatchFlowError::Client)?;
        let request = self
            .request_without_timeout(
                v1::WatchProjectChangesRequest {
                    project_id: project_id.to_string(),
                    since_revision,
                },
                &token,
            )
            .map_err(WatchFlowError::Client)?;
        let mut service = self.service.clone();
        let response = tokio::select! {
            _ = cancel.cancelled() => return Err(WatchFlowError::Client(ClientError::Cancelled)),
            response = tokio::time::timeout(WATCH_HEARTBEAT_TIMEOUT, service.watch_project_changes(request)) => {
                match response {
                    Ok(Ok(response)) => response,
                    Ok(Err(status)) => return Err(WatchFlowError::Client(ClientError::from(status))),
                    Err(_) => return Err(WatchFlowError::Client(ClientError::Unavailable("watch open timeout".to_owned()))),
                }
            }
        };
        let mut stream = response.into_inner();
        let mut current_revision = since_revision;
        loop {
            let message = tokio::select! {
                _ = cancel.cancelled() => return Err(WatchFlowError::Client(ClientError::Cancelled)),
                result = tokio::time::timeout(WATCH_HEARTBEAT_TIMEOUT, stream.message()) => {
                    match result {
                        Ok(Ok(Some(message))) => message,
                        Ok(Ok(None)) => return Err(WatchFlowError::Client(ClientError::Unavailable("watch stream closed".to_owned()))),
                        Ok(Err(status)) => return Err(WatchFlowError::Client(ClientError::from(status))),
                        Err(_) => return Err(WatchFlowError::Client(ClientError::Unavailable("watch heartbeat timeout".to_owned()))),
                    }
                }
            };
            let payload = message.payload.ok_or_else(|| {
                WatchFlowError::Client(ClientError::Protocol(
                    "watch response has no payload".to_owned(),
                ))
            })?;
            match payload {
                v1::watch_project_changes_response::Payload::Event(change) => {
                    let event = change_event_from_proto(change, project_id)
                        .map_err(WatchFlowError::Client)?;
                    if event.project_id != project_id {
                        return Err(WatchFlowError::Client(ClientError::Protocol(
                            "watch event project_id does not match request".to_owned(),
                        )));
                    }
                    if event.revision <= current_revision {
                        continue;
                    }
                    if event.revision != current_revision.saturating_add(1) {
                        self.snapshots.clear_project(project_id);
                        return Err(WatchFlowError::Client(ClientError::ResetRequired {
                            current_revision,
                            minimum_retained_revision: 0,
                            reason: ResetReason::RetentionGap,
                        }));
                    }
                    match self.snapshots.apply_event(&event) {
                        EventApplyResult::Applied { revision } => {
                            current_revision = revision;
                            tx.send(ClientEvent::Change(event))
                                .await
                                .map_err(|_| WatchFlowError::ReceiverClosed)?;
                        }
                        EventApplyResult::AlreadyApplied => {}
                        EventApplyResult::Gap { .. }
                        | EventApplyResult::NotCached
                        | EventApplyResult::Invalid
                        | EventApplyResult::BudgetExceeded => {
                            return Err(WatchFlowError::Client(ClientError::ResetRequired {
                                current_revision,
                                minimum_retained_revision: 0,
                                reason: ResetReason::RetentionGap,
                            }));
                        }
                    }
                }
                v1::watch_project_changes_response::Payload::Heartbeat(heartbeat) => {
                    if heartbeat.project_revision > current_revision {
                        self.snapshots.clear_project(project_id);
                        return Err(WatchFlowError::Client(ClientError::ResetRequired {
                            current_revision,
                            minimum_retained_revision: 0,
                            reason: ResetReason::AheadOfServer,
                        }));
                    }
                }
                v1::watch_project_changes_response::Payload::ResetRequired(reset) => {
                    self.snapshots.clear_project(project_id);
                    return Err(WatchFlowError::Client(ClientError::ResetRequired {
                        current_revision: reset.current_revision,
                        minimum_retained_revision: reset.minimum_retained_revision,
                        reason: reset_reason_from_text(&reset.reason),
                    }));
                }
            }
        }
    }

    fn request<T>(
        &self,
        message: T,
        deadline: Duration,
        token: &AuthToken,
    ) -> Result<Request<T>, ClientError> {
        let mut request = self.request_without_timeout(message, token)?;
        request.set_timeout(deadline);
        Ok(request)
    }

    fn request_without_timeout<T>(
        &self,
        message: T,
        token: &AuthToken,
    ) -> Result<Request<T>, ClientError> {
        let mut request = Request::new(message);
        request
            .metadata_mut()
            .insert("authorization", token.authorization_value()?);
        Ok(request)
    }

    async fn required_token(&self) -> Result<AuthToken, ClientError> {
        self.token
            .read()
            .await
            .clone()
            .ok_or(ClientError::AuthenticationRequired)
    }

    async fn update_cache_for_error(&self, error: &ClientError, project_id: Option<Uuid>) {
        match error {
            ClientError::Unauthenticated => {
                *self.token.write().await = None;
                self.clear_caches();
            }
            ClientError::PermissionDenied => {
                if let Some(project_id) = project_id {
                    self.snapshots.clear_project(project_id);
                }
            }
            _ => {}
        }
    }
}

enum WatchFlowError {
    Client(ClientError),
    ReceiverClosed,
}

async fn send_reconnecting(
    tx: &mpsc::Sender<ClientEvent>,
    attempt: u32,
    delay: Duration,
) -> Result<(), ()> {
    tx.send(ClientEvent::Reconnecting(ReconnectNotice {
        attempt,
        retry_in_ms: u64::try_from(delay.as_millis()).unwrap_or(u64::MAX),
    }))
    .await
    .map_err(|_| ())
}

async fn sleep_or_cancel(delay: Duration, cancel: &CancellationToken) -> bool {
    tokio::select! {
        _ = cancel.cancelled() => false,
        _ = tokio::time::sleep(delay) => true,
    }
}

fn normalize_deadline_error(error: ClientError, deadline_at: Instant) -> ClientError {
    if matches!(error, ClientError::Cancelled) && Instant::now() >= deadline_at {
        ClientError::DeadlineExceeded
    } else {
        error
    }
}

fn watch_delay(attempt: u32) -> Duration {
    let policy = crate::RetryPolicy {
        max_attempts: 10,
        initial_delay: Duration::from_millis(500),
        max_delay: Duration::from_secs(30),
    };
    jittered_retry_delay(policy, attempt.min(WATCH_MAX_BACKOFF_EXPONENT))
}

fn project_summary_from_proto(value: v1::Project) -> Result<ProjectSummary, ClientError> {
    let project = project_from_proto(value)?;
    Ok(ProjectSummary {
        id: project.id,
        name: project.name,
        time_zone: project.time_zone,
        current_revision: project.current_revision,
    })
}

fn project_snapshot_from_proto(
    value: v1::GetProjectSnapshotResponse,
) -> Result<ProjectSnapshot, ClientError> {
    let schema_version = value
        .schema_version
        .parse::<u32>()
        .map_err(|_| ClientError::Protocol("snapshot schema version is invalid".to_owned()))?;
    if schema_version != domain::SCHEMA_VERSION {
        return Err(ClientError::Protocol(format!(
            "unsupported snapshot schema version {schema_version}"
        )));
    }
    let project = value
        .project
        .ok_or_else(|| ClientError::Protocol("snapshot.project is required".to_owned()))?;
    let project = project_from_proto(project)?;
    if project.current_revision != value.revision {
        return Err(ClientError::Protocol(
            "snapshot revision does not match project.revision".to_owned(),
        ));
    }
    let user_names = value
        .users
        .into_iter()
        .map(|user| parse_uuid("user.id", &user.id).map(|id| (id, user.display_name)))
        .collect::<Result<std::collections::HashMap<_, _>, _>>()?;
    let members = value
        .members
        .into_iter()
        .map(|member| {
            let user_id = parse_uuid("member.user_id", &member.user_id)?;
            Ok(ProjectMember {
                user_id,
                display_name: user_names.get(&user_id).cloned().unwrap_or_default(),
                role: project_role_from_proto(member.role)?,
            })
        })
        .collect::<Result<Vec<_>, ClientError>>()?;
    let tasks = value
        .tasks
        .into_iter()
        .map(task_from_proto)
        .collect::<Result<Vec<_>, _>>()?;
    let audit = value
        .audit
        .into_iter()
        .map(project_audit_entry_from_proto)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(ProjectSnapshot {
        project,
        members,
        tasks,
        audit,
        generated_at: timestamp_to_datetime("generated_at", value.generated_at.as_ref())?,
    })
}

fn project_audit_entry_from_proto(
    value: v1::ProjectAuditEntry,
) -> Result<ProjectAuditEntry, ClientError> {
    Ok(ProjectAuditEntry {
        id: parse_uuid("audit.id", &value.id)?,
        revision: value.revision,
        action: value.action,
        summary: value.summary,
        task_id: value
            .task_id
            .as_deref()
            .map(|task_id| parse_uuid("audit.task_id", task_id))
            .transpose()?,
        actor_id: parse_uuid("audit.actor_id", &value.actor_id)?,
        occurred_at: timestamp_to_datetime("audit.occurred_at", value.occurred_at.as_ref())?,
    })
}

fn project_from_proto(value: v1::Project) -> Result<Project, ClientError> {
    Ok(Project {
        id: parse_uuid("project.id", &value.id)?,
        name: value.name,
        time_zone: value.time_zone,
        current_revision: value.revision,
        created_at: timestamp_to_datetime("project.created_at", value.created_at.as_ref())?,
        updated_at: timestamp_to_datetime("project.updated_at", value.updated_at.as_ref())?,
    })
}

fn task_from_proto(value: v1::Task) -> Result<Task, ClientError> {
    if value.version == 0 {
        return Err(ClientError::Protocol(
            "task.version must be nonzero".to_owned(),
        ));
    }
    Ok(Task {
        id: parse_uuid("task.id", &value.id)?,
        project_id: parse_uuid("task.project_id", &value.project_id)?,
        title: value.title,
        description_markdown: value.description_markdown,
        status: task_status_from_proto(value.status)?,
        priority: task_priority_from_proto(value.priority)?,
        assignee_ids: parse_uuid_list(&value.assignee_ids, "task.assignee_ids")?,
        planned_on: parse_required_date(&value.planned_on, "task.planned_on")?,
        starts_on: parse_optional_date(value.starts_on.as_deref(), "task.starts_on")?,
        due_on: parse_optional_date(value.due_on.as_deref(), "task.due_on")?,
        tags: value.tags,
        parent_task_id: parse_optional_uuid(
            value.parent_task_id.as_deref(),
            "task.parent_task_id",
        )?,
        dependency_task_ids: parse_uuid_list(
            &value.dependency_task_ids,
            "task.dependency_task_ids",
        )?,
        version: value.version,
        created_by: parse_uuid("task.created_by", &value.created_by)?,
        updated_by: parse_uuid("task.updated_by", &value.updated_by)?,
        created_at: timestamp_to_datetime("task.created_at", value.created_at.as_ref())?,
        updated_at: timestamp_to_datetime("task.updated_at", value.updated_at.as_ref())?,
    })
}

fn change_event_from_proto(
    value: v1::ProjectChangeEvent,
    expected_project_id: Uuid,
) -> Result<ChangeEvent, ClientError> {
    contract::collapse_change_event(value, expected_project_id).map_err(map_api_error)
}

fn command_outcome_from_proto(
    value: v1::ExecuteCommandResponse,
) -> Result<CommandOutcome, ClientError> {
    let result = value
        .result
        .ok_or_else(|| ClientError::Protocol("command result is required".to_owned()))?;
    let command_id = parse_uuid("result.command_id", &result.command_id)?;
    if result.project_revision == 0 {
        return Err(ClientError::Protocol(
            "command project revision must be nonzero".to_owned(),
        ));
    }
    let event = result
        .event
        .ok_or_else(|| ClientError::Protocol("command event is required".to_owned()))?;
    if event.revision != result.project_revision {
        return Err(ClientError::Protocol(
            "command event revision does not match project revision".to_owned(),
        ));
    }
    let project_id = parse_uuid("command.event.project_id", &event.project_id)?;
    let event = change_event_from_proto(event, project_id)?;
    if event.command_id != command_id {
        return Err(ClientError::Protocol(
            "command event command_id does not match result".to_owned(),
        ));
    }
    Ok(CommandOutcome {
        command_id,
        revision: result.project_revision,
        event,
    })
}

fn command_envelope_to_proto(value: &CommandEnvelope) -> Result<v1::CommandEnvelope, ClientError> {
    let command = match &value.command {
        Command::CreateProject { name, time_zone } => {
            v1::command_envelope::Command::CreateProject(v1::CreateProjectCommand {
                name: name.clone(),
                time_zone: time_zone.clone(),
            })
        }
        Command::AddProjectMember { user_id, role } => {
            v1::command_envelope::Command::AddProjectMember(v1::AddProjectMemberCommand {
                user_id: user_id.to_string(),
                role: contract::project_role_to_proto(*role) as i32,
            })
        }
        Command::CreateTask {
            task_id: _,
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
        } => v1::command_envelope::Command::CreateTask(v1::CreateTaskCommand {
            draft: Some(v1::TaskDraft {
                title: title.clone(),
                description_markdown: description_markdown.clone(),
                status: task_status_to_proto(*status) as i32,
                priority: task_priority_to_proto(*priority) as i32,
                assignee_ids: assignee_ids.iter().map(ToString::to_string).collect(),
                planned_on: planned_on.format("%Y-%m-%d").to_string(),
                starts_on: starts_on.map(|value| value.format("%Y-%m-%d").to_string()),
                due_on: due_on.map(|value| value.format("%Y-%m-%d").to_string()),
                tags: tags.clone(),
                parent_task_id: parent_task_id.map(|value| value.to_string()),
                dependency_task_ids: dependency_task_ids
                    .iter()
                    .map(ToString::to_string)
                    .collect(),
            }),
        }),
        Command::UpdateTask {
            task_id,
            expected_entity_version,
            patch,
        } => v1::command_envelope::Command::UpdateTask(v1::UpdateTaskCommand {
            task_id: task_id.to_string(),
            expected_entity_version: *expected_entity_version,
            patch: Some(task_patch_to_proto(patch)?),
        }),
        Command::DeleteTask {
            task_id,
            expected_entity_version,
        } => v1::command_envelope::Command::DeleteTask(v1::DeleteTaskCommand {
            task_id: task_id.to_string(),
            expected_entity_version: *expected_entity_version,
        }),
        Command::BatchUpdateTasks { mutations } => {
            v1::command_envelope::Command::BatchUpdateTasks(v1::BatchUpdateTasksCommand {
                mutations: mutations
                    .iter()
                    .map(task_mutation_to_proto)
                    .collect::<Result<Vec<_>, _>>()?,
            })
        }
    };
    Ok(v1::CommandEnvelope {
        client_id: value.client_id.to_string(),
        command_id: value.command_id.to_string(),
        project_id: value.project_id.to_string(),
        expected_project_revision: value.expected_revision,
        command: Some(command),
    })
}

fn task_mutation_to_proto(value: &TaskMutation) -> Result<v1::TaskMutation, ClientError> {
    let mutation = match value {
        TaskMutation::CreateTask {
            task_id: _,
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
        } => v1::task_mutation::Mutation::CreateTask(v1::CreateTaskCommand {
            draft: Some(v1::TaskDraft {
                title: title.clone(),
                description_markdown: description_markdown.clone(),
                status: task_status_to_proto(*status) as i32,
                priority: task_priority_to_proto(*priority) as i32,
                assignee_ids: assignee_ids.iter().map(ToString::to_string).collect(),
                planned_on: planned_on.format("%Y-%m-%d").to_string(),
                starts_on: starts_on.map(|value| value.format("%Y-%m-%d").to_string()),
                due_on: due_on.map(|value| value.format("%Y-%m-%d").to_string()),
                tags: tags.clone(),
                parent_task_id: parent_task_id.map(|value| value.to_string()),
                dependency_task_ids: dependency_task_ids
                    .iter()
                    .map(ToString::to_string)
                    .collect(),
            }),
        }),
        TaskMutation::UpdateTask {
            task_id,
            expected_entity_version,
            patch,
        } => v1::task_mutation::Mutation::UpdateTask(v1::UpdateTaskCommand {
            task_id: task_id.to_string(),
            expected_entity_version: *expected_entity_version,
            patch: Some(task_patch_to_proto(patch)?),
        }),
        TaskMutation::DeleteTask {
            task_id,
            expected_entity_version,
        } => v1::task_mutation::Mutation::DeleteTask(v1::DeleteTaskCommand {
            task_id: task_id.to_string(),
            expected_entity_version: *expected_entity_version,
        }),
    };
    Ok(v1::TaskMutation {
        mutation: Some(mutation),
    })
}

fn task_patch_to_proto(patch: &TaskPatch) -> Result<v1::TaskPatch, ClientError> {
    Ok(v1::TaskPatch {
        title: maybe_value(&patch.title, "title")?,
        description_markdown: maybe_value(&patch.description_markdown, "description_markdown")?,
        status: maybe_mapped(&patch.status, "status", |value| {
            task_status_to_proto(*value) as i32
        })?,
        priority: maybe_mapped(&patch.priority, "priority", |value| {
            task_priority_to_proto(*value) as i32
        })?,
        assignee_ids: uuid_list_patch(&patch.assignee_ids)?,
        planned_on: required_date_patch(&patch.planned_on, "planned_on")?,
        starts_on: optional_date_patch(&patch.starts_on)?,
        due_on: optional_date_patch(&patch.due_on)?,
        tags: string_list_patch(&patch.tags)?,
        parent_task_id: optional_uuid_patch(&patch.parent_task_id)?,
        dependency_task_ids: uuid_list_patch(&patch.dependency_task_ids)?,
    })
}

fn maybe_value<T: Clone>(value: &Maybe<T>, field: &'static str) -> Result<Option<T>, ClientError> {
    match value {
        Maybe::Unset => Ok(None),
        Maybe::Value(value) => Ok(Some(value.clone())),
        Maybe::Null => Err(ClientError::InvalidArgument(format!(
            "{field} cannot be null"
        ))),
    }
}

fn maybe_mapped<T, U, F>(
    value: &Maybe<T>,
    field: &'static str,
    map: F,
) -> Result<Option<U>, ClientError>
where
    F: FnOnce(&T) -> U,
{
    match value {
        Maybe::Unset => Ok(None),
        Maybe::Value(value) => Ok(Some(map(value))),
        Maybe::Null => Err(ClientError::InvalidArgument(format!(
            "{field} cannot be null"
        ))),
    }
}

fn uuid_list_patch(value: &Maybe<Vec<Uuid>>) -> Result<Option<v1::StringList>, ClientError> {
    match value {
        Maybe::Unset => Ok(None),
        Maybe::Null => Err(ClientError::InvalidArgument(
            "UUID list patch cannot be null".to_owned(),
        )),
        Maybe::Value(values) => Ok(Some(v1::StringList {
            values: values.iter().map(ToString::to_string).collect(),
        })),
    }
}

fn string_list_patch(value: &Maybe<Vec<String>>) -> Result<Option<v1::StringList>, ClientError> {
    match value {
        Maybe::Unset => Ok(None),
        Maybe::Null => Err(ClientError::InvalidArgument(
            "string list patch cannot be null".to_owned(),
        )),
        Maybe::Value(values) => Ok(Some(v1::StringList {
            values: values.clone(),
        })),
    }
}

fn required_date_patch(
    value: &Maybe<NaiveDate>,
    field: &'static str,
) -> Result<Option<String>, ClientError> {
    match value {
        Maybe::Unset => Ok(None),
        Maybe::Value(value) => Ok(Some(value.format("%Y-%m-%d").to_string())),
        Maybe::Null => Err(ClientError::InvalidArgument(format!(
            "{field} cannot be null"
        ))),
    }
}

fn optional_uuid_patch(value: &Maybe<Option<Uuid>>) -> Result<Option<String>, ClientError> {
    match value {
        Maybe::Unset => Ok(None),
        Maybe::Null => Ok(Some(String::new())),
        Maybe::Value(Some(value)) => Ok(Some(value.to_string())),
        Maybe::Value(None) => Ok(Some(String::new())),
    }
}

fn optional_date_patch(value: &Maybe<Option<NaiveDate>>) -> Result<Option<String>, ClientError> {
    match value {
        Maybe::Unset => Ok(None),
        Maybe::Null => Ok(Some(String::new())),
        Maybe::Value(Some(value)) => Ok(Some(value.format("%Y-%m-%d").to_string())),
        Maybe::Value(None) => Ok(Some(String::new())),
    }
}

fn parse_uuid(field: &'static str, value: &str) -> Result<Uuid, ClientError> {
    Uuid::parse_str(value)
        .map_err(|_| ClientError::Protocol(format!("{field} is not a valid UUID")))
}

fn parse_uuid_list(values: &[String], field: &'static str) -> Result<Vec<Uuid>, ClientError> {
    values
        .iter()
        .map(|value| parse_uuid(field, value))
        .collect()
}

fn parse_optional_uuid(
    value: Option<&str>,
    field: &'static str,
) -> Result<Option<Uuid>, ClientError> {
    value
        .filter(|value| !value.is_empty())
        .map(|value| parse_uuid(field, value))
        .transpose()
}

fn parse_required_date(value: &str, field: &'static str) -> Result<NaiveDate, ClientError> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ClientError::Protocol(format!("{field} is not a YYYY-MM-DD date")))
}

fn parse_optional_date(
    value: Option<&str>,
    field: &'static str,
) -> Result<Option<NaiveDate>, ClientError> {
    value
        .filter(|value| !value.is_empty())
        .map(|value| parse_required_date(value, field))
        .transpose()
}

fn timestamp_to_datetime(
    field: &'static str,
    value: Option<&Timestamp>,
) -> Result<DateTime<Utc>, ClientError> {
    let value = value.ok_or_else(|| ClientError::Protocol(format!("{field} is required")))?;
    let nanos = u32::try_from(value.nanos)
        .ok()
        .filter(|nanos| *nanos < 1_000_000_000)
        .ok_or_else(|| ClientError::Protocol(format!("{field} has invalid nanoseconds")))?;
    DateTime::from_timestamp(value.seconds, nanos)
        .ok_or_else(|| ClientError::Protocol(format!("{field} is not a valid timestamp")))
}

fn project_role_from_proto(value: i32) -> Result<domain::ProjectRole, ClientError> {
    contract::project_role_from_proto(value)
        .map_err(|error| ClientError::Protocol(error.to_string()))
}

fn task_status_from_proto(value: i32) -> Result<TaskStatus, ClientError> {
    match v1::TaskStatus::try_from(value) {
        Ok(v1::TaskStatus::Todo) => Ok(TaskStatus::Todo),
        Ok(v1::TaskStatus::InProgress) => Ok(TaskStatus::InProgress),
        Ok(v1::TaskStatus::Blocked) => Ok(TaskStatus::Blocked),
        Ok(v1::TaskStatus::Done) => Ok(TaskStatus::Done),
        _ => Err(ClientError::Protocol(format!(
            "unknown task status {value}"
        ))),
    }
}

fn task_status_to_proto(value: TaskStatus) -> v1::TaskStatus {
    match value {
        TaskStatus::Todo => v1::TaskStatus::Todo,
        TaskStatus::InProgress => v1::TaskStatus::InProgress,
        TaskStatus::Blocked => v1::TaskStatus::Blocked,
        TaskStatus::Done => v1::TaskStatus::Done,
    }
}

fn task_priority_from_proto(value: i32) -> Result<TaskPriority, ClientError> {
    match v1::TaskPriority::try_from(value) {
        Ok(v1::TaskPriority::None) => Ok(TaskPriority::None),
        Ok(v1::TaskPriority::Low) => Ok(TaskPriority::Low),
        Ok(v1::TaskPriority::Medium) => Ok(TaskPriority::Medium),
        Ok(v1::TaskPriority::High) => Ok(TaskPriority::High),
        Ok(v1::TaskPriority::Urgent) => Ok(TaskPriority::Urgent),
        _ => Err(ClientError::Protocol(format!(
            "unknown task priority {value}"
        ))),
    }
}

fn task_priority_to_proto(value: TaskPriority) -> v1::TaskPriority {
    match value {
        TaskPriority::None => v1::TaskPriority::None,
        TaskPriority::Low => v1::TaskPriority::Low,
        TaskPriority::Medium => v1::TaskPriority::Medium,
        TaskPriority::High => v1::TaskPriority::High,
        TaskPriority::Urgent => v1::TaskPriority::Urgent,
    }
}

fn map_api_error(error: contract::ApiError) -> ClientError {
    match error {
        contract::ApiError::InvalidArgument(message) => ClientError::InvalidArgument(message),
        contract::ApiError::Unauthenticated => ClientError::Unauthenticated,
        contract::ApiError::PermissionDenied => ClientError::PermissionDenied,
        contract::ApiError::NotFound(message) => ClientError::NotFound(message),
        contract::ApiError::Conflict {
            current_revision,
            entity_id,
            current_entity_version,
        } => ClientError::Conflict(crate::ConflictDetails {
            current_revision,
            entity_id,
            current_entity_version,
        }),
        contract::ApiError::ResetRequired {
            current_revision,
            minimum_retained_revision,
            reason,
        } => ClientError::ResetRequired {
            current_revision,
            minimum_retained_revision,
            reason,
        },
        contract::ApiError::AlreadyExists(message) => ClientError::AlreadyExists(message),
        contract::ApiError::ResourceExhausted(message) => ClientError::ResourceExhausted(message),
        contract::ApiError::FailedPrecondition(message)
        | contract::ApiError::Unsupported(message) => ClientError::FailedPrecondition(message),
        contract::ApiError::Unavailable(message) => ClientError::Unavailable(message),
        contract::ApiError::DeadlineExceeded => ClientError::DeadlineExceeded,
        contract::ApiError::Cancelled => ClientError::Cancelled,
        contract::ApiError::Internal => {
            ClientError::Internal("contract conversion failed".to_owned())
        }
    }
}

fn reset_reason_from_text(value: &str) -> ResetReason {
    match value {
        "ahead_of_server" => ResetReason::AheadOfServer,
        "schema_mismatch" => ResetReason::SchemaMismatch,
        "corrupt_stream" => ResetReason::CorruptStream,
        "backpressure" => ResetReason::Backpressure,
        _ => ResetReason::RetentionGap,
    }
}

fn reset_reason_name(value: ResetReason) -> &'static str {
    match value {
        ResetReason::RetentionGap => "retention_gap",
        ResetReason::AheadOfServer => "ahead_of_server",
        ResetReason::SchemaMismatch => "schema_mismatch",
        ResetReason::CorruptStream => "corrupt_stream",
        ResetReason::Backpressure => "backpressure",
    }
}

impl std::fmt::Debug for KshiftClient {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KshiftClient")
            .field("endpoint", &self.config.endpoint())
            .field("cache", &self.snapshots.stats())
            .finish_non_exhaustive()
    }
}
