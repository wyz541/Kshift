//! Shared protobuf contract and wire/domain conversions.

use chrono::{DateTime, NaiveDate, Utc};
use domain::{
    Change, ChangeEvent, Command, CommandEnvelope, DomainError, Maybe, ProjectMember, ProjectRole,
    ProjectSnapshot, ResetReason, Task, TaskPatch, TaskPriority, TaskStatus,
};
use prost::Message;
use sha2::{Digest, Sha256};
use thiserror::Error;
use tonic::{Code, Status};
use uuid::Uuid;

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
            Self::FailedPrecondition(_) => Code::FailedPrecondition,
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
            reset_reason,
        ) = match self {
            Self::InvalidArgument(message) => (
                v1::ErrorCode::InvalidInput,
                message.clone(),
                None,
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
                None,
            ),
            Self::PermissionDenied => (
                v1::ErrorCode::Forbidden,
                "permission denied".to_owned(),
                None,
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
                None,
            ),
            Self::ResetRequired {
                current_revision,
                minimum_retained_revision,
                reason,
            } => (
                v1::ErrorCode::ResetRequired,
                "client must fetch a new snapshot".to_owned(),
                Some(*current_revision),
                None,
                None,
                Some(*minimum_retained_revision),
                Some(reset_reason_to_proto(*reason)),
            ),
            Self::AlreadyExists(message) => (
                v1::ErrorCode::AlreadyExists,
                message.clone(),
                None,
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
                None,
            ),
            Self::FailedPrecondition(message) => (
                v1::ErrorCode::FailedPrecondition,
                message.clone(),
                None,
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
                None,
            ),
            Self::DeadlineExceeded => (
                v1::ErrorCode::Internal,
                "request deadline exceeded".to_owned(),
                None,
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
                None,
            ),
            Self::Internal => (
                v1::ErrorCode::Internal,
                "internal server error".to_owned(),
                None,
                None,
                None,
                None,
                None,
            ),
        };

        let detail = v1::ErrorDetail {
            code: error_code as i32,
            message: message.clone(),
            current_project_revision: current_revision,
            entity_id,
            current_entity_version,
            minimum_retained_revision,
            reset_reason: reset_reason.map(|value| value as i32),
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
        .envelope
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
        },
        v1::command_envelope::Command::AddProjectMember(command) => Command::AddProjectMember {
            user_id: parse_uuid(&command.user_id, "user_id")?,
            role: project_role_from_proto(command.role)?,
        },
        v1::command_envelope::Command::CreateTask(command) => Command::CreateTask {
            task_id: parse_uuid(&command.task_id, "task_id")?,
            title: command.title.clone(),
            description: command.description.clone(),
            status: task_status_from_proto_or_default(command.status)?,
            priority: task_priority_from_proto_or_default(command.priority)?,
            assignee_id: parse_optional_uuid(command.assignee_id.as_deref(), "assignee_id")?,
            due_date: parse_optional_date(command.due_date.as_deref(), "due_date")?,
        },
        v1::command_envelope::Command::UpdateTask(command) => Command::UpdateTask {
            task_id: parse_uuid(&command.task_id, "task_id")?,
            expected_entity_version: command.expected_entity_version,
            patch: TaskPatch {
                title: command.title.clone().map_or(Maybe::Unset, Maybe::Value),
                description: command
                    .description
                    .clone()
                    .map_or(Maybe::Unset, Maybe::Value),
                status: command
                    .status
                    .map(task_status_from_proto)
                    .transpose()?
                    .map_or(Maybe::Unset, Maybe::Value),
                priority: command
                    .priority
                    .map(task_priority_from_proto)
                    .transpose()?
                    .map_or(Maybe::Unset, Maybe::Value),
                assignee_id: parse_optional_uuid_patch(
                    command.assignee_id.as_deref(),
                    "assignee_id",
                )?,
                due_date: parse_optional_date_patch(command.due_date.as_deref(), "due_date")?,
            },
        },
        v1::command_envelope::Command::DeleteTask(command) => Command::DeleteTask {
            task_id: parse_uuid(&command.task_id, "task_id")?,
            expected_entity_version: command.expected_entity_version,
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

pub fn project_snapshot_to_proto(value: &ProjectSnapshot) -> v1::ProjectSnapshot {
    v1::ProjectSnapshot {
        schema_version: domain::SCHEMA_VERSION,
        revision: value.project.current_revision,
        project: Some(project_to_proto(&value.project)),
        users: value
            .members
            .iter()
            .map(|member| v1::ProjectUser {
                id: member.user_id.to_string(),
                display_name: member.display_name.clone(),
            })
            .collect(),
        members: value.members.iter().map(project_member_to_proto).collect(),
        tasks: value.tasks.iter().map(task_to_proto).collect(),
        generated_at: Some(datetime_to_timestamp(value.generated_at)),
    }
}

pub fn project_to_proto(value: &domain::Project) -> v1::Project {
    v1::Project {
        id: value.id.to_string(),
        name: value.name.clone(),
        current_revision: value.current_revision,
        created_at: Some(datetime_to_timestamp(value.created_at)),
        updated_at: Some(datetime_to_timestamp(value.updated_at)),
    }
}

pub fn project_summary_to_proto(value: &domain::Project, role: ProjectRole) -> v1::ProjectSummary {
    v1::ProjectSummary {
        id: value.id.to_string(),
        name: value.name.clone(),
        current_revision: value.current_revision,
        role: project_role_to_proto(role) as i32,
    }
}

pub fn project_member_to_proto(value: &ProjectMember) -> v1::ProjectMember {
    v1::ProjectMember {
        user: Some(v1::ProjectUser {
            id: value.user_id.to_string(),
            display_name: value.display_name.clone(),
        }),
        role: project_role_to_proto(value.role) as i32,
    }
}

pub fn task_to_proto(value: &Task) -> v1::Task {
    v1::Task {
        id: value.id.to_string(),
        project_id: value.project_id.to_string(),
        title: value.title.clone(),
        description: value.description.clone(),
        status: task_status_to_proto(value.status) as i32,
        priority: task_priority_to_proto(value.priority) as i32,
        assignee_id: value.assignee_id.map(|value| value.to_string()),
        due_date: value
            .due_date
            .map(|value| value.format("%Y-%m-%d").to_string()),
        version: value.version,
        created_by: value.created_by.to_string(),
        updated_by: value.updated_by.to_string(),
        created_at: Some(datetime_to_timestamp(value.created_at)),
        updated_at: Some(datetime_to_timestamp(value.updated_at)),
    }
}

pub fn change_event_to_proto(value: &ChangeEvent) -> v1::ProjectChangeEvent {
    let change = match &value.change {
        Change::ProjectCreated { project_id, name } => {
            v1::project_change_event::Change::ProjectCreated(v1::ProjectCreated {
                project_id: project_id.to_string(),
                name: name.clone(),
            })
        }
        Change::ProjectMemberUpserted { member } => {
            v1::project_change_event::Change::ProjectMemberUpserted(v1::ProjectMemberUpserted {
                member: Some(project_member_to_proto(member)),
            })
        }
        Change::TaskCreated { task } => {
            v1::project_change_event::Change::TaskCreated(v1::TaskCreated {
                task: Some(task_to_proto(task)),
            })
        }
        Change::TaskUpdated { task } => {
            v1::project_change_event::Change::TaskUpdated(v1::TaskUpdated {
                task: Some(task_to_proto(task)),
            })
        }
        Change::TaskDeleted { task_id, version } => {
            v1::project_change_event::Change::TaskDeleted(v1::TaskDeleted {
                task_id: task_id.to_string(),
                version: *version,
            })
        }
    };

    v1::ProjectChangeEvent {
        project_id: value.project_id.to_string(),
        revision: value.revision,
        schema_version: value.schema_version,
        command_id: value.command_id.to_string(),
        occurred_at: Some(datetime_to_timestamp(value.occurred_at)),
        change: Some(change),
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
    let command_id = parse_uuid(&value.command_id, "event.command_id")?;
    let occurred_at = value
        .occurred_at
        .as_ref()
        .and_then(timestamp_to_datetime)
        .ok_or_else(|| ApiError::FailedPrecondition("event timestamp is invalid".to_owned()))?;
    let change = match value
        .change
        .ok_or_else(|| ApiError::FailedPrecondition("event does not contain a change".to_owned()))?
    {
        v1::project_change_event::Change::ProjectCreated(change) => Change::ProjectCreated {
            project_id: parse_uuid(&change.project_id, "event.project_created.project_id")?,
            name: change.name,
        },
        v1::project_change_event::Change::ProjectMemberUpserted(change) => {
            Change::ProjectMemberUpserted {
                member: project_member_from_proto(change.member.ok_or_else(|| {
                    ApiError::FailedPrecondition("event member is missing".to_owned())
                })?)?,
            }
        }
        v1::project_change_event::Change::TaskCreated(change) => Change::TaskCreated {
            task: task_from_proto(change.task.ok_or_else(|| {
                ApiError::FailedPrecondition("event task is missing".to_owned())
            })?)?,
        },
        v1::project_change_event::Change::TaskUpdated(change) => Change::TaskUpdated {
            task: task_from_proto(change.task.ok_or_else(|| {
                ApiError::FailedPrecondition("event task is missing".to_owned())
            })?)?,
        },
        v1::project_change_event::Change::TaskDeleted(change) => Change::TaskDeleted {
            task_id: parse_uuid(&change.task_id, "event.task_deleted.task_id")?,
            version: change.version,
        },
    };

    Ok(ChangeEvent {
        project_id,
        revision: value.revision,
        schema_version: value.schema_version,
        command_id,
        occurred_at,
        change,
    })
}

fn project_member_from_proto(value: v1::ProjectMember) -> Result<ProjectMember, ApiError> {
    let user = value
        .user
        .ok_or_else(|| ApiError::FailedPrecondition("member user is missing".to_owned()))?;
    Ok(ProjectMember {
        user_id: parse_uuid(&user.id, "member.user.id")?,
        display_name: user.display_name,
        role: project_role_from_proto(value.role)?,
    })
}

fn task_from_proto(value: v1::Task) -> Result<Task, ApiError> {
    Ok(Task {
        id: parse_uuid(&value.id, "task.id")?,
        project_id: parse_uuid(&value.project_id, "task.project_id")?,
        title: value.title,
        description: value.description,
        status: task_status_from_proto_or_default(value.status)?,
        priority: task_priority_from_proto_or_default(value.priority)?,
        assignee_id: parse_optional_uuid(value.assignee_id.as_deref(), "task.assignee_id")?,
        due_date: parse_optional_date(value.due_date.as_deref(), "task.due_date")?,
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

fn parse_optional_date(value: Option<&str>, field: &str) -> Result<Option<NaiveDate>, ApiError> {
    match value {
        None | Some("") => Ok(None),
        Some(value) => NaiveDate::parse_from_str(value, "%Y-%m-%d")
            .map(Some)
            .map_err(|_| ApiError::InvalidArgument(format!("{field} must use YYYY-MM-DD"))),
    }
}

fn parse_optional_date_patch(
    value: Option<&str>,
    field: &str,
) -> Result<Maybe<Option<NaiveDate>>, ApiError> {
    match value {
        None => Ok(Maybe::Unset),
        Some("") => Ok(Maybe::Null),
        Some(value) => NaiveDate::parse_from_str(value, "%Y-%m-%d")
            .map(|value| Maybe::Value(Some(value)))
            .map_err(|_| ApiError::InvalidArgument(format!("{field} must use YYYY-MM-DD"))),
    }
}

pub fn project_role_to_proto(value: ProjectRole) -> v1::ProjectRole {
    match value {
        ProjectRole::Viewer => v1::ProjectRole::Viewer,
        ProjectRole::Editor => v1::ProjectRole::Editor,
        ProjectRole::Owner => v1::ProjectRole::Owner,
    }
}

pub fn project_role_from_proto(value: i32) -> Result<ProjectRole, ApiError> {
    match v1::ProjectRole::try_from(value) {
        Ok(v1::ProjectRole::Viewer) => Ok(ProjectRole::Viewer),
        Ok(v1::ProjectRole::Editor) => Ok(ProjectRole::Editor),
        Ok(v1::ProjectRole::Owner) => Ok(ProjectRole::Owner),
        _ => Err(ApiError::InvalidArgument(
            "role must be VIEWER, EDITOR, or OWNER".to_owned(),
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
        TaskPriority::Low => v1::TaskPriority::Low,
        TaskPriority::Medium => v1::TaskPriority::Medium,
        TaskPriority::High => v1::TaskPriority::High,
        TaskPriority::Urgent => v1::TaskPriority::Urgent,
    }
}

fn task_priority_from_proto_or_default(value: i32) -> Result<TaskPriority, ApiError> {
    match v1::TaskPriority::try_from(value) {
        Ok(v1::TaskPriority::Unspecified) => Ok(TaskPriority::Medium),
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
        Ok(v1::TaskPriority::Low) => Ok(TaskPriority::Low),
        Ok(v1::TaskPriority::Medium) => Ok(TaskPriority::Medium),
        Ok(v1::TaskPriority::High) => Ok(TaskPriority::High),
        Ok(v1::TaskPriority::Urgent) => Ok(TaskPriority::Urgent),
        Err(_) => Err(ApiError::InvalidArgument(
            "task priority is invalid".to_owned(),
        )),
    }
}

fn reset_reason_to_proto(value: ResetReason) -> v1::ResetReason {
    match value {
        ResetReason::RetentionGap => v1::ResetReason::RetentionGap,
        ResetReason::AheadOfServer => v1::ResetReason::AheadOfServer,
        ResetReason::SchemaMismatch => v1::ResetReason::SchemaMismatch,
        ResetReason::CorruptStream => v1::ResetReason::CorruptStream,
        ResetReason::Backpressure => v1::ResetReason::Backpressure,
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
        let request = v1::ExecuteCommandRequest {
            envelope: Some(v1::CommandEnvelope {
                client_id: Uuid::new_v4().to_string(),
                command_id: Uuid::new_v4().to_string(),
                project_id: Uuid::new_v4().to_string(),
                expected_project_revision: Some(1),
                command: None,
            }),
        };

        assert!(matches!(
            parse_execute_command(&request),
            Err(ApiError::InvalidArgument(_))
        ));
    }
}
