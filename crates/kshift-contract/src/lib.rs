//! Shared protobuf contract and wire/domain conversions.

mod plan_depth;

pub use plan_depth::{
    parse_execute_plan_depth_command, plan_actor_role_from_proto, plan_actor_role_to_proto,
    plan_command_response_to_proto, plan_depth_command_to_proto, plan_depth_snapshot_from_proto,
    plan_depth_snapshot_to_proto, plan_error_to_api, plan_report_from_proto, plan_report_to_proto,
    PlanDepthCommandInput,
};

use std::collections::HashSet;

use chrono::{DateTime, NaiveDate, Utc};
use domain::{
    Change, ChangeEvent, Command, CommandEnvelope, DomainError, Maybe, ProjectAuditEntry,
    ProjectMember, ProjectRole, ProjectSnapshot, ResetReason, Task, TaskMutation, TaskPatch,
    TaskPriority, TaskStatus,
};
use prost::Message;
use sha2::{Digest, Sha256};
use thiserror::Error;
use tonic::{Code, Status};
use uuid::Uuid;

/// Maximum encoded size of one unary request.
pub const MAX_UNARY_REQUEST_BYTES: usize = 1_048_576;
/// Maximum encoded size of one unary response or project snapshot.
pub const MAX_UNARY_RESPONSE_BYTES: usize = 16_777_216;
/// Maximum encoded size of one project change event.
pub const MAX_EVENT_BYTES: usize = 262_144;
/// Maximum size of one attachment returned to a client.
pub const MAX_ATTACHMENT_BYTES: usize = 268_435_456;

#[allow(clippy::all)]
pub mod v1 {
    tonic::include_proto!("kshift.v1");
}

pub use v1::kshift_service_client::KshiftServiceClient;
pub use v1::kshift_service_server::{KshiftService, KshiftServiceServer};

#[derive(Clone, Debug, Error)]
pub enum ApiError {
    #[error("{0}")]
    InvalidArgument(String),
    #[error("authentication is required")]
    Unauthenticated,
    #[error("permission denied")]
    PermissionDenied,
    #[error("{0}")]
    NotFound(String),
    #[error("revision or entity version conflict")]
    Conflict {
        current_revision: Option<u64>,
        entity_id: Option<Uuid>,
        current_entity_version: Option<u64>,
    },
    #[error("client must fetch a new snapshot")]
    ResetRequired {
        current_revision: u64,
        minimum_retained_revision: u64,
        reason: ResetReason,
    },
    #[error("{0}")]
    AlreadyExists(String),
    #[error("{0}")]
    ResourceExhausted(String),
    #[error("{0}")]
    FailedPrecondition(String),
    #[error("{0}")]
    Unavailable(String),
    #[error("{0}")]
    Unsupported(String),
    #[error("request deadline exceeded")]
    DeadlineExceeded,
    #[error("request cancelled")]
    Cancelled,
    #[error("internal server error")]
    Internal,
}

impl From<DomainError> for ApiError {
    fn from(value: DomainError) -> Self {
        match value {
            DomainError::Validation(message) => Self::InvalidArgument(message),
            DomainError::NotFound(message) => Self::NotFound(message),
            DomainError::PermissionDenied => Self::PermissionDenied,
            DomainError::Conflict {
                current_revision,
                entity_id,
                current_entity_version,
            } => Self::Conflict {
                current_revision,
                entity_id,
                current_entity_version,
            },
            DomainError::ResetRequired {
                current_revision,
                minimum_retained_revision,
                reason,
            } => Self::ResetRequired {
                current_revision,
                minimum_retained_revision,
                reason,
            },
            DomainError::AlreadyExists(message) => Self::AlreadyExists(message),
            DomainError::Unsupported(message) => Self::Unsupported(message),
        }
    }
}

impl ApiError {
    pub fn to_status(&self) -> Status {
        let code = match self {
            Self::InvalidArgument(_) => Code::InvalidArgument,
            Self::Unauthenticated => Code::Unauthenticated,
            Self::PermissionDenied => Code::PermissionDenied,
            Self::NotFound(_) => Code::NotFound,
            Self::Conflict { .. } => Code::Aborted,
            Self::ResetRequired { .. } => Code::FailedPrecondition,
            Self::AlreadyExists(_) => Code::AlreadyExists,
            Self::ResourceExhausted(_) => Code::ResourceExhausted,
            Self::FailedPrecondition(_) | Self::Unsupported(_) => Code::FailedPrecondition,
            Self::Unavailable(_) => Code::Unavailable,
            Self::DeadlineExceeded => Code::DeadlineExceeded,
            Self::Cancelled => Code::Cancelled,
            Self::Internal => Code::Internal,
        };

        let (
            error_code,
            message,
            current_revision,
            entity_id,
            current_entity_version,
            minimum_retained_revision,
        ) = match self {
            Self::InvalidArgument(message) => (
                v1::ErrorCode::InvalidInput,
                message.clone(),
                None,
                None,
                None,
                None,
            ),
            Self::Unauthenticated => (
                v1::ErrorCode::AuthRequired,
                "authentication is required".to_owned(),
                None,
                None,
                None,
                None,
            ),
            Self::PermissionDenied => (
                v1::ErrorCode::Forbidden,
                "permission denied".to_owned(),
                None,
                None,
                None,
                None,
            ),
            Self::NotFound(message) => (
                v1::ErrorCode::InvalidState,
                message.clone(),
                None,
                None,
                None,
                None,
            ),
            Self::Conflict {
                current_revision,
                entity_id,
                current_entity_version,
            } => (
                v1::ErrorCode::Conflict,
                "revision or entity version conflict".to_owned(),
                *current_revision,
                entity_id.map(|value| value.to_string()),
                *current_entity_version,
                None,
            ),
            Self::ResetRequired {
                current_revision,
                minimum_retained_revision,
                reason: _,
            } => (
                v1::ErrorCode::ResetRequired,
                "client must fetch a new snapshot".to_owned(),
                Some(*current_revision),
                None,
                None,
                Some(*minimum_retained_revision),
            ),
            Self::AlreadyExists(message) => (
                v1::ErrorCode::AlreadyExists,
                message.clone(),
                None,
                None,
                None,
                None,
            ),
            Self::ResourceExhausted(message) => (
                v1::ErrorCode::LimitExceeded,
                message.clone(),
                None,
                None,
                None,
                None,
            ),
            Self::FailedPrecondition(message) | Self::Unsupported(message) => (
                v1::ErrorCode::FailedPrecondition,
                message.clone(),
                None,
                None,
                None,
                None,
            ),
            Self::Unavailable(message) => (
                v1::ErrorCode::Internal,
                message.clone(),
                None,
                None,
                None,
                None,
            ),
            Self::DeadlineExceeded => (
                v1::ErrorCode::Internal,
                "request deadline exceeded".to_owned(),
                None,
                None,
                None,
                None,
            ),
            Self::Cancelled => (
                v1::ErrorCode::Internal,
                "request cancelled".to_owned(),
                None,
                None,
                None,
                None,
            ),
            Self::Internal => (
                v1::ErrorCode::Internal,
                "internal server error".to_owned(),
                None,
                None,
                None,
                None,
            ),
        };

        let detail = v1::ErrorDetail {
            code: error_code as i32,
            message: message.clone(),
            request_id: String::new(),
            project_id: String::new(),
            entity_id: entity_id.unwrap_or_default(),
            current_project_revision: current_revision,
            current_entity_version,
            minimum_retained_revision,
        };

        Status::with_details(code, message, detail.encode_to_vec().into())
    }
}

pub fn error_detail(status: &Status) -> Result<v1::ErrorDetail, prost::DecodeError> {
    v1::ErrorDetail::decode(status.details())
}

#[derive(Clone, Debug)]
pub struct ParsedCommand {
    pub envelope: CommandEnvelope,
    pub request_digest: Vec<u8>,
}

pub fn parse_execute_command(
    request: &v1::ExecuteCommandRequest,
) -> Result<ParsedCommand, ApiError> {
    let request_digest = Sha256::digest(request.encode_to_vec()).to_vec();
    let envelope = request
        .command
        .as_ref()
        .ok_or_else(|| ApiError::InvalidArgument("command envelope is required".to_owned()))?;
    let client_id = parse_uuid(&envelope.client_id, "client_id")?;
    let command_id = parse_uuid(&envelope.command_id, "command_id")?;
    let project_id = parse_uuid(&envelope.project_id, "project_id")?;

    let command = match envelope.command.as_ref().ok_or_else(|| {
        ApiError::InvalidArgument("command must contain exactly one typed command".to_owned())
    })? {
        v1::command_envelope::Command::CreateProject(command) => Command::CreateProject {
            name: command.name.clone(),
            time_zone: command.time_zone.clone(),
        },
        v1::command_envelope::Command::AddProjectMember(command) => Command::AddProjectMember {
            user_id: parse_uuid(&command.user_id, "user_id")?,
            role: project_role_from_proto(command.role)?,
        },
        v1::command_envelope::Command::CreateTask(command) => {
            let draft = command.draft.as_ref().ok_or_else(|| {
                ApiError::InvalidArgument("create_task draft is required".to_owned())
            })?;
            Command::CreateTask {
                task_id: Uuid::new_v4(),
                title: draft.title.clone(),
                description_markdown: draft.description_markdown.clone(),
                status: task_status_from_proto_or_default(draft.status)?,
                priority: task_priority_from_proto_or_default(draft.priority)?,
                assignee_ids: parse_uuid_list(&draft.assignee_ids, "assignee_ids")?,
                planned_on: parse_required_date(&draft.planned_on, "planned_on")?,
                starts_on: parse_optional_date(draft.starts_on.as_deref(), "starts_on")?,
                due_on: parse_optional_date(draft.due_on.as_deref(), "due_on")?,
                tags: draft.tags.clone(),
                parent_task_id: parse_optional_uuid(
                    draft.parent_task_id.as_deref(),
                    "parent_task_id",
                )?,
                dependency_task_ids: parse_uuid_list(
                    &draft.dependency_task_ids,
                    "dependency_task_ids",
                )?,
            }
        }
        v1::command_envelope::Command::UpdateTask(command) => Command::UpdateTask {
            task_id: parse_uuid(&command.task_id, "task_id")?,
            expected_entity_version: command.expected_entity_version,
            patch: parse_task_patch(command.patch.as_ref())?,
        },
        v1::command_envelope::Command::DeleteTask(command) => Command::DeleteTask {
            task_id: parse_uuid(&command.task_id, "task_id")?,
            expected_entity_version: command.expected_entity_version,
        },
        v1::command_envelope::Command::BatchUpdateTasks(command) => Command::BatchUpdateTasks {
            mutations: command
                .mutations
                .iter()
                .cloned()
                .map(parse_task_mutation)
                .collect::<Result<Vec<_>, _>>()?,
        },
    };

    let envelope = CommandEnvelope {
        client_id,
        command_id,
        project_id,
        expected_revision: envelope.expected_project_revision,
        command,
    };
    envelope.validate().map_err(ApiError::from)?;

    Ok(ParsedCommand {
        envelope,
        request_digest,
    })
}

fn parse_task_patch(patch: Option<&v1::TaskPatch>) -> Result<TaskPatch, ApiError> {
    let patch = patch
        .ok_or_else(|| ApiError::InvalidArgument("update task patch is required".to_owned()))?;
    Ok(TaskPatch {
        title: patch.title.clone().map_or(Maybe::Unset, Maybe::Value),
        description_markdown: patch
            .description_markdown
            .clone()
            .map_or(Maybe::Unset, Maybe::Value),
        status: patch
            .status
            .map(task_status_from_proto)
            .transpose()?
            .map_or(Maybe::Unset, Maybe::Value),
        priority: patch
            .priority
            .map(task_priority_from_proto)
            .transpose()?
            .map_or(Maybe::Unset, Maybe::Value),
        assignee_ids: patch
            .assignee_ids
            .as_ref()
            .map(|value| parse_uuid_list(&value.values, "assignee_ids"))
            .transpose()?
            .map_or(Maybe::Unset, Maybe::Value),
        planned_on: patch
            .planned_on
            .as_deref()
            .map(|value| parse_required_date(value, "planned_on"))
            .transpose()?
            .map_or(Maybe::Unset, Maybe::Value),
        starts_on: parse_optional_date_patch(patch.starts_on.as_deref(), "starts_on")?,
        due_on: parse_optional_date_patch(patch.due_on.as_deref(), "due_on")?,
        tags: patch
            .tags
            .as_ref()
            .map(|value| Maybe::Value(value.values.clone()))
            .unwrap_or_default(),
        parent_task_id: parse_optional_uuid_patch(
            patch.parent_task_id.as_deref(),
            "parent_task_id",
        )?,
        dependency_task_ids: patch
            .dependency_task_ids
            .as_ref()
            .map(|value| parse_uuid_list(&value.values, "dependency_task_ids"))
            .transpose()?
            .map_or(Maybe::Unset, Maybe::Value),
    })
}

fn parse_task_mutation(value: v1::TaskMutation) -> Result<TaskMutation, ApiError> {
    match value.mutation.ok_or_else(|| {
        ApiError::InvalidArgument("batch_update_tasks mutation is required".to_owned())
    })? {
        v1::task_mutation::Mutation::CreateTask(command) => {
            let draft = command.draft.ok_or_else(|| {
                ApiError::InvalidArgument("batch create_task draft is required".to_owned())
            })?;
            Ok(TaskMutation::CreateTask {
                task_id: Uuid::new_v4(),
                title: draft.title,
                description_markdown: draft.description_markdown,
                status: task_status_from_proto_or_default(draft.status)?,
                priority: task_priority_from_proto_or_default(draft.priority)?,
                assignee_ids: parse_uuid_list(&draft.assignee_ids, "assignee_ids")?,
                planned_on: parse_required_date(&draft.planned_on, "planned_on")?,
                starts_on: parse_optional_date(draft.starts_on.as_deref(), "starts_on")?,
                due_on: parse_optional_date(draft.due_on.as_deref(), "due_on")?,
                tags: draft.tags,
                parent_task_id: parse_optional_uuid(
                    draft.parent_task_id.as_deref(),
                    "parent_task_id",
                )?,
                dependency_task_ids: parse_uuid_list(
                    &draft.dependency_task_ids,
                    "dependency_task_ids",
                )?,
            })
        }
        v1::task_mutation::Mutation::UpdateTask(command) => Ok(TaskMutation::UpdateTask {
            task_id: parse_uuid(&command.task_id, "task_id")?,
            expected_entity_version: command.expected_entity_version,
            patch: parse_task_patch(command.patch.as_ref())?,
        }),
        v1::task_mutation::Mutation::DeleteTask(command) => Ok(TaskMutation::DeleteTask {
            task_id: parse_uuid(&command.task_id, "task_id")?,
            expected_entity_version: command.expected_entity_version,
        }),
    }
}

pub fn project_to_proto(value: &domain::Project) -> v1::Project {
    v1::Project {
        id: value.id.to_string(),
        name: value.name.clone(),
        time_zone: value.time_zone.clone(),
        revision: value.current_revision,
        created_at: Some(datetime_to_timestamp(value.created_at)),
        updated_at: Some(datetime_to_timestamp(value.updated_at)),
    }
}

pub fn project_snapshot_to_proto(value: &ProjectSnapshot) -> v1::GetProjectSnapshotResponse {
    v1::GetProjectSnapshotResponse {
        schema_version: domain::SCHEMA_VERSION.to_string(),
        revision: value.project.current_revision,
        project: Some(project_to_proto(&value.project)),
        users: value
            .members
            .iter()
            .map(|member| v1::User {
                id: member.user_id.to_string(),
                display_name: member.display_name.clone(),
                email: None,
            })
            .collect(),
        members: value.members.iter().map(project_member_to_proto).collect(),
        tasks: value.tasks.iter().map(task_to_proto).collect(),
        generated_at: Some(datetime_to_timestamp(value.generated_at)),
        audit: value
            .audit
            .iter()
            .map(project_audit_entry_to_proto)
            .collect(),
    }
}

pub fn project_audit_entry_to_proto(value: &ProjectAuditEntry) -> v1::ProjectAuditEntry {
    v1::ProjectAuditEntry {
        id: value.id.to_string(),
        revision: value.revision,
        action: value.action.clone(),
        summary: value.summary.clone(),
        task_id: value.task_id.map(|task_id| task_id.to_string()),
        actor_id: value.actor_id.to_string(),
        occurred_at: Some(datetime_to_timestamp(value.occurred_at)),
    }
}

pub fn project_member_to_proto(value: &ProjectMember) -> v1::ProjectMember {
    v1::ProjectMember {
        user_id: value.user_id.to_string(),
        role: project_role_to_proto(value.role) as i32,
    }
}

pub fn task_to_proto(value: &Task) -> v1::Task {
    v1::Task {
        id: value.id.to_string(),
        project_id: value.project_id.to_string(),
        title: value.title.clone(),
        description_markdown: value.description_markdown.clone(),
        status: task_status_to_proto(value.status) as i32,
        priority: task_priority_to_proto(value.priority) as i32,
        assignee_ids: value.assignee_ids.iter().map(ToString::to_string).collect(),
        planned_on: value.planned_on.format("%Y-%m-%d").to_string(),
        starts_on: value
            .starts_on
            .map(|value| value.format("%Y-%m-%d").to_string()),
        due_on: value
            .due_on
            .map(|value| value.format("%Y-%m-%d").to_string()),
        tags: value.tags.clone(),
        parent_task_id: value.parent_task_id.map(|value| value.to_string()),
        dependency_task_ids: value
            .dependency_task_ids
            .iter()
            .map(ToString::to_string)
            .collect(),
        version: value.version,
        created_by: value.created_by.to_string(),
        updated_by: value.updated_by.to_string(),
        created_at: Some(datetime_to_timestamp(value.created_at)),
        updated_at: Some(datetime_to_timestamp(value.updated_at)),
    }
}

pub fn change_event_to_proto(value: &ChangeEvent) -> v1::ProjectChangeEvent {
    v1::ProjectChangeEvent {
        schema_version: value.schema_version.to_string(),
        project_id: value.project_id.to_string(),
        revision: value.revision,
        command_id: value.command_id.to_string(),
        changes: value
            .changes
            .iter()
            .map(|change| v1::Change {
                change: Some(change_to_proto(change)),
            })
            .collect(),
        committed_at: Some(datetime_to_timestamp(value.occurred_at)),
    }
}

fn change_to_proto(value: &Change) -> v1::change::Change {
    match value {
        Change::ProjectUpserted { project } => {
            v1::change::Change::ProjectUpserted(v1::ProjectUpserted {
                project: Some(project_to_proto(project)),
            })
        }
        Change::ProjectMemberUpserted { member } => {
            v1::change::Change::MemberUpserted(v1::ProjectMemberUpserted {
                member: Some(project_member_to_proto(member)),
            })
        }
        Change::TaskCreated { task } | Change::TaskUpdated { task } => {
            v1::change::Change::TaskUpserted(v1::TaskUpserted {
                task: Some(task_to_proto(task)),
            })
        }
        Change::TaskDeleted { task_id } => v1::change::Change::TaskDeleted(v1::TaskDeleted {
            task_id: task_id.to_string(),
        }),
    }
}

pub fn collapse_change_event(
    value: v1::ProjectChangeEvent,
    expected_project_id: Uuid,
) -> Result<ChangeEvent, ApiError> {
    let project_id = parse_uuid(&value.project_id, "event.project_id")?;
    if project_id != expected_project_id {
        return Err(ApiError::FailedPrecondition(
            "event project does not match stream project".to_owned(),
        ));
    }
    let schema_version = value
        .schema_version
        .parse::<u32>()
        .map_err(|_| ApiError::FailedPrecondition("event schema version is invalid".to_owned()))?;
    let command_id = parse_uuid(&value.command_id, "event.command_id")?;
    let occurred_at = value
        .committed_at
        .as_ref()
        .and_then(timestamp_to_datetime)
        .ok_or_else(|| ApiError::FailedPrecondition("event timestamp is invalid".to_owned()))?;
    if value.changes.is_empty() {
        return Err(ApiError::FailedPrecondition(
            "event must contain at least one change".to_owned(),
        ));
    }
    let changes = value
        .changes
        .into_iter()
        .map(change_from_proto)
        .collect::<Result<Vec<_>, _>>()?;

    Ok(ChangeEvent {
        project_id,
        revision: value.revision,
        schema_version,
        command_id,
        occurred_at,
        changes,
    })
}

fn change_from_proto(value: v1::Change) -> Result<Change, ApiError> {
    match value.change {
        Some(v1::change::Change::ProjectUpserted(change)) => Ok(Change::ProjectUpserted {
            project: project_from_proto(change.project.ok_or_else(|| {
                ApiError::FailedPrecondition("event project is missing".to_owned())
            })?)?,
        }),
        Some(v1::change::Change::MemberUpserted(change)) => Ok(Change::ProjectMemberUpserted {
            member: project_member_from_proto(change.member.ok_or_else(|| {
                ApiError::FailedPrecondition("event member is missing".to_owned())
            })?)?,
        }),
        Some(v1::change::Change::TaskUpserted(change)) => Ok(Change::TaskUpdated {
            task: task_from_proto(change.task.ok_or_else(|| {
                ApiError::FailedPrecondition("event task is missing".to_owned())
            })?)?,
        }),
        Some(v1::change::Change::TaskDeleted(change)) => Ok(Change::TaskDeleted {
            task_id: parse_uuid(&change.task_id, "event.task_deleted.task_id")?,
        }),
        Some(v1::change::Change::MemberDeleted(_)) | None => Err(ApiError::FailedPrecondition(
            "event contains an unsupported change".to_owned(),
        )),
    }
}

fn project_from_proto(value: v1::Project) -> Result<domain::Project, ApiError> {
    Ok(domain::Project {
        id: parse_uuid(&value.id, "project.id")?,
        name: value.name,
        time_zone: value.time_zone,
        current_revision: value.revision,
        created_at: value
            .created_at
            .as_ref()
            .and_then(timestamp_to_datetime)
            .ok_or_else(|| {
                ApiError::FailedPrecondition("project.created_at is invalid".to_owned())
            })?,
        updated_at: value
            .updated_at
            .as_ref()
            .and_then(timestamp_to_datetime)
            .ok_or_else(|| {
                ApiError::FailedPrecondition("project.updated_at is invalid".to_owned())
            })?,
    })
}

fn project_member_from_proto(value: v1::ProjectMember) -> Result<ProjectMember, ApiError> {
    Ok(ProjectMember {
        user_id: parse_uuid(&value.user_id, "member.user_id")?,
        display_name: String::new(),
        role: project_role_from_proto(value.role)?,
    })
}

fn task_from_proto(value: v1::Task) -> Result<Task, ApiError> {
    Ok(Task {
        id: parse_uuid(&value.id, "task.id")?,
        project_id: parse_uuid(&value.project_id, "task.project_id")?,
        title: value.title,
        description_markdown: value.description_markdown,
        status: task_status_from_proto_or_default(value.status)?,
        priority: task_priority_from_proto_or_default(value.priority)?,
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
        created_by: parse_uuid(&value.created_by, "task.created_by")?,
        updated_by: parse_uuid(&value.updated_by, "task.updated_by")?,
        created_at: value
            .created_at
            .as_ref()
            .and_then(timestamp_to_datetime)
            .ok_or_else(|| ApiError::FailedPrecondition("task.created_at is invalid".to_owned()))?,
        updated_at: value
            .updated_at
            .as_ref()
            .and_then(timestamp_to_datetime)
            .ok_or_else(|| ApiError::FailedPrecondition("task.updated_at is invalid".to_owned()))?,
    })
}

fn parse_uuid(value: &str, field: &str) -> Result<Uuid, ApiError> {
    Uuid::parse_str(value).map_err(|_| ApiError::InvalidArgument(format!("{field} must be a UUID")))
}

fn parse_uuid_list(values: &[String], field: &str) -> Result<Vec<Uuid>, ApiError> {
    let mut parsed = Vec::with_capacity(values.len());
    let mut seen = HashSet::with_capacity(values.len());
    for value in values {
        let id = parse_uuid(value, field)?;
        if id.is_nil() {
            return Err(ApiError::InvalidArgument(format!(
                "{field} must not contain nil UUIDs"
            )));
        }
        if !seen.insert(id) {
            return Err(ApiError::InvalidArgument(format!(
                "{field} must not contain duplicates"
            )));
        }
        parsed.push(id);
    }
    Ok(parsed)
}

fn parse_optional_uuid(value: Option<&str>, field: &str) -> Result<Option<Uuid>, ApiError> {
    match value {
        None | Some("") => Ok(None),
        Some(value) => parse_uuid(value, field).map(Some),
    }
}

fn parse_optional_uuid_patch(
    value: Option<&str>,
    field: &str,
) -> Result<Maybe<Option<Uuid>>, ApiError> {
    match value {
        None => Ok(Maybe::Unset),
        Some("") => Ok(Maybe::Null),
        Some(value) => parse_uuid(value, field).map(|value| Maybe::Value(Some(value))),
    }
}

fn parse_required_date(value: &str, field: &str) -> Result<NaiveDate, ApiError> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ApiError::InvalidArgument(format!("{field} must use YYYY-MM-DD")))
}

fn parse_optional_date(value: Option<&str>, field: &str) -> Result<Option<NaiveDate>, ApiError> {
    match value {
        None | Some("") => Ok(None),
        Some(value) => parse_required_date(value, field).map(Some),
    }
}

fn parse_optional_date_patch(
    value: Option<&str>,
    field: &str,
) -> Result<Maybe<Option<NaiveDate>>, ApiError> {
    match value {
        None => Ok(Maybe::Unset),
        Some("") => Ok(Maybe::Null),
        Some(value) => parse_required_date(value, field).map(|value| Maybe::Value(Some(value))),
    }
}

pub fn project_role_to_proto(value: ProjectRole) -> v1::ProjectRole {
    match value {
        ProjectRole::Viewer => v1::ProjectRole::Viewer,
        ProjectRole::Editor => v1::ProjectRole::Editor,
        ProjectRole::Admin => v1::ProjectRole::Admin,
    }
}

pub fn project_role_from_proto(value: i32) -> Result<ProjectRole, ApiError> {
    match v1::ProjectRole::try_from(value) {
        Ok(v1::ProjectRole::Viewer) => Ok(ProjectRole::Viewer),
        Ok(v1::ProjectRole::Editor) => Ok(ProjectRole::Editor),
        Ok(v1::ProjectRole::Admin) => Ok(ProjectRole::Admin),
        _ => Err(ApiError::InvalidArgument(
            "role must be VIEWER, EDITOR, or ADMIN".to_owned(),
        )),
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

fn task_status_from_proto_or_default(value: i32) -> Result<TaskStatus, ApiError> {
    match v1::TaskStatus::try_from(value) {
        Ok(v1::TaskStatus::Unspecified) => Ok(TaskStatus::Todo),
        Ok(v1::TaskStatus::Todo) => Ok(TaskStatus::Todo),
        Ok(v1::TaskStatus::InProgress) => Ok(TaskStatus::InProgress),
        Ok(v1::TaskStatus::Blocked) => Ok(TaskStatus::Blocked),
        Ok(v1::TaskStatus::Done) => Ok(TaskStatus::Done),
        Err(_) => Err(ApiError::InvalidArgument(
            "task status is invalid".to_owned(),
        )),
    }
}

fn task_status_from_proto(value: i32) -> Result<TaskStatus, ApiError> {
    match v1::TaskStatus::try_from(value) {
        Ok(v1::TaskStatus::Unspecified) => Err(ApiError::InvalidArgument(
            "task status must not be unspecified".to_owned(),
        )),
        Ok(v1::TaskStatus::Todo) => Ok(TaskStatus::Todo),
        Ok(v1::TaskStatus::InProgress) => Ok(TaskStatus::InProgress),
        Ok(v1::TaskStatus::Blocked) => Ok(TaskStatus::Blocked),
        Ok(v1::TaskStatus::Done) => Ok(TaskStatus::Done),
        Err(_) => Err(ApiError::InvalidArgument(
            "task status is invalid".to_owned(),
        )),
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

fn task_priority_from_proto_or_default(value: i32) -> Result<TaskPriority, ApiError> {
    match v1::TaskPriority::try_from(value) {
        Ok(v1::TaskPriority::Unspecified) => Ok(TaskPriority::Medium),
        Ok(v1::TaskPriority::None) => Ok(TaskPriority::None),
        Ok(v1::TaskPriority::Low) => Ok(TaskPriority::Low),
        Ok(v1::TaskPriority::Medium) => Ok(TaskPriority::Medium),
        Ok(v1::TaskPriority::High) => Ok(TaskPriority::High),
        Ok(v1::TaskPriority::Urgent) => Ok(TaskPriority::Urgent),
        Err(_) => Err(ApiError::InvalidArgument(
            "task priority is invalid".to_owned(),
        )),
    }
}

fn task_priority_from_proto(value: i32) -> Result<TaskPriority, ApiError> {
    match v1::TaskPriority::try_from(value) {
        Ok(v1::TaskPriority::Unspecified) => Err(ApiError::InvalidArgument(
            "task priority must not be unspecified".to_owned(),
        )),
        Ok(v1::TaskPriority::None) => Ok(TaskPriority::None),
        Ok(v1::TaskPriority::Low) => Ok(TaskPriority::Low),
        Ok(v1::TaskPriority::Medium) => Ok(TaskPriority::Medium),
        Ok(v1::TaskPriority::High) => Ok(TaskPriority::High),
        Ok(v1::TaskPriority::Urgent) => Ok(TaskPriority::Urgent),
        Err(_) => Err(ApiError::InvalidArgument(
            "task priority is invalid".to_owned(),
        )),
    }
}

pub fn reset_reason_to_string(value: ResetReason) -> &'static str {
    match value {
        ResetReason::RetentionGap => "retention_gap",
        ResetReason::AheadOfServer => "ahead_of_server",
        ResetReason::SchemaMismatch => "schema_mismatch",
        ResetReason::CorruptStream => "corrupt_stream",
        ResetReason::Backpressure => "backpressure",
    }
}

fn datetime_to_timestamp(value: DateTime<Utc>) -> prost_types::Timestamp {
    prost_types::Timestamp {
        seconds: value.timestamp(),
        nanos: value.timestamp_subsec_nanos() as i32,
    }
}

fn timestamp_to_datetime(value: &prost_types::Timestamp) -> Option<DateTime<Utc>> {
    DateTime::from_timestamp(value.seconds, u32::try_from(value.nanos).ok()?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_status_contains_typed_conflict_detail() {
        let status = ApiError::Conflict {
            current_revision: Some(42),
            entity_id: Some(Uuid::nil()),
            current_entity_version: Some(7),
        }
        .to_status();

        let detail = error_detail(&status).expect("detail should decode");
        assert_eq!(status.code(), Code::Aborted);
        assert_eq!(detail.code, v1::ErrorCode::Conflict as i32);
        assert_eq!(detail.current_project_revision, Some(42));
        assert_eq!(detail.current_entity_version, Some(7));
    }

    #[test]
    fn invalid_typed_command_is_rejected() {
        let request = v1::ExecuteCommandRequest { command: None };

        assert!(matches!(
            parse_execute_command(&request),
            Err(ApiError::InvalidArgument(_))
        ));
    }
}
