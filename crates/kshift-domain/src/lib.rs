//! Pure Kshift business types and invariants. This crate performs no I/O.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

pub const SCHEMA_VERSION: u32 = 1;
pub const MAX_PROJECT_NAME_CHARS: usize = 120;
pub const MAX_TASK_TITLE_CHARS: usize = 200;
pub const MAX_TASK_DESCRIPTION_CHARS: usize = 20_000;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProjectRole {
    Viewer,
    Editor,
    Owner,
}

impl ProjectRole {
    pub fn can_read(self) -> bool {
        true
    }

    pub fn can_write(self) -> bool {
        matches!(self, Self::Editor | Self::Owner)
    }

    pub fn can_manage_members(self) -> bool {
        matches!(self, Self::Owner)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Todo,
    InProgress,
    Blocked,
    Done,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskPriority {
    Low,
    Medium,
    High,
    Urgent,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Project {
    pub id: Uuid,
    pub name: String,
    pub current_revision: u64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ProjectMember {
    pub user_id: Uuid,
    pub display_name: String,
    pub role: ProjectRole,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub id: Uuid,
    pub project_id: Uuid,
    pub title: String,
    pub description: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub assignee_id: Option<Uuid>,
    pub due_date: Option<NaiveDate>,
    pub version: u64,
    pub created_by: Uuid,
    pub updated_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ProjectSnapshot {
    pub project: Project,
    pub members: Vec<ProjectMember>,
    pub tasks: Vec<Task>,
    pub generated_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub enum Maybe<T> {
    #[default]
    Unset,
    Null,
    Value(T),
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct TaskPatch {
    pub title: Maybe<String>,
    pub description: Maybe<String>,
    pub status: Maybe<TaskStatus>,
    pub priority: Maybe<TaskPriority>,
    pub assignee_id: Maybe<Option<Uuid>>,
    pub due_date: Maybe<Option<NaiveDate>>,
}

impl TaskPatch {
    pub fn is_empty(&self) -> bool {
        matches!(self.title, Maybe::Unset)
            && matches!(self.description, Maybe::Unset)
            && matches!(self.status, Maybe::Unset)
            && matches!(self.priority, Maybe::Unset)
            && matches!(self.assignee_id, Maybe::Unset)
            && matches!(self.due_date, Maybe::Unset)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Command {
    CreateProject {
        name: String,
    },
    AddProjectMember {
        user_id: Uuid,
        role: ProjectRole,
    },
    CreateTask {
        task_id: Uuid,
        title: String,
        description: String,
        status: TaskStatus,
        priority: TaskPriority,
        assignee_id: Option<Uuid>,
        due_date: Option<NaiveDate>,
    },
    UpdateTask {
        task_id: Uuid,
        expected_entity_version: u64,
        patch: TaskPatch,
    },
    DeleteTask {
        task_id: Uuid,
        expected_entity_version: u64,
    },
}

impl Command {
    pub fn name(&self) -> &'static str {
        match self {
            Self::CreateProject { .. } => "create_project",
            Self::AddProjectMember { .. } => "add_project_member",
            Self::CreateTask { .. } => "create_task",
            Self::UpdateTask { .. } => "update_task",
            Self::DeleteTask { .. } => "delete_task",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CommandEnvelope {
    pub client_id: Uuid,
    pub command_id: Uuid,
    pub project_id: Uuid,
    pub expected_revision: Option<u64>,
    pub command: Command,
}

impl CommandEnvelope {
    pub fn validate(&self) -> Result<(), DomainError> {
        match &self.command {
            Command::CreateProject { name } => {
                if !matches!(self.expected_revision, None | Some(0)) {
                    return Err(validation(
                        "create_project expected_project_revision must be absent or 0",
                    ));
                }
                validate_project_name(name)
            }
            Command::AddProjectMember { .. } => {
                require_project_revision(self.expected_revision, "add_project_member")
            }
            Command::CreateTask {
                title, description, ..
            } => {
                require_project_revision(self.expected_revision, "create_task")?;
                validate_task_title(title)?;
                validate_description(description)
            }
            Command::UpdateTask {
                expected_entity_version,
                patch,
                ..
            } => {
                validate_optional_project_revision(self.expected_revision, "update_task")?;
                if *expected_entity_version == 0 {
                    return Err(validation("update_task entity version must be nonzero"));
                }
                if patch.is_empty() {
                    return Err(validation(
                        "update_task patch must contain at least one field",
                    ));
                }
                validate_patch(patch)
            }
            Command::DeleteTask {
                expected_entity_version,
                ..
            } => {
                validate_optional_project_revision(self.expected_revision, "delete_task")?;
                if *expected_entity_version == 0 {
                    return Err(validation("delete_task entity version must be nonzero"));
                }
                Ok(())
            }
        }?;

        if self.project_id.is_nil() {
            return Err(validation("project_id must not be nil"));
        }
        if self.client_id.is_nil() {
            return Err(validation("client_id must not be nil"));
        }
        if self.command_id.is_nil() {
            return Err(validation("command_id must not be nil"));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Change {
    ProjectCreated { project_id: Uuid, name: String },
    ProjectMemberUpserted { member: ProjectMember },
    TaskCreated { task: Task },
    TaskUpdated { task: Task },
    TaskDeleted { task_id: Uuid, version: u64 },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChangeEvent {
    pub project_id: Uuid,
    pub revision: u64,
    pub schema_version: u32,
    pub command_id: Uuid,
    pub occurred_at: DateTime<Utc>,
    pub change: Change,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ResetReason {
    RetentionGap,
    AheadOfServer,
    SchemaMismatch,
    CorruptStream,
    Backpressure,
}

#[derive(Debug, Error, Eq, PartialEq)]
pub enum DomainError {
    #[error("{0}")]
    Validation(String),
    #[error("{0}")]
    NotFound(String),
    #[error("permission denied")]
    PermissionDenied,
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
}

pub fn update_task(task: &Task, patch: &TaskPatch, actor_id: Uuid) -> Result<Task, DomainError> {
    validate_patch(patch)?;
    let mut next = task.clone();
    apply_maybe(&mut next.title, &patch.title, |value| {
        validate_task_title(value)
    })?;
    apply_maybe(&mut next.description, &patch.description, |value| {
        validate_description(value)
    })?;
    apply_maybe(&mut next.status, &patch.status, |_| Ok(()))?;
    apply_maybe(&mut next.priority, &patch.priority, |_| Ok(()))?;
    apply_optional(&mut next.assignee_id, &patch.assignee_id)?;
    apply_optional(&mut next.due_date, &patch.due_date)?;
    next.version = next
        .version
        .checked_add(1)
        .ok_or_else(|| validation("task version overflow"))?;
    next.updated_by = actor_id;
    next.updated_at = Utc::now();
    Ok(next)
}

fn apply_maybe<T, F>(target: &mut T, patch: &Maybe<T>, validate: F) -> Result<(), DomainError>
where
    T: Clone,
    F: Fn(&T) -> Result<(), DomainError>,
{
    match patch {
        Maybe::Unset => Ok(()),
        Maybe::Null => Err(validation("field cannot be null")),
        Maybe::Value(value) => {
            validate(value)?;
            *target = value.clone();
            Ok(())
        }
    }
}

fn apply_optional<T: Clone>(
    target: &mut Option<T>,
    patch: &Maybe<Option<T>>,
) -> Result<(), DomainError> {
    match patch {
        Maybe::Unset => Ok(()),
        Maybe::Null => {
            *target = None;
            Ok(())
        }
        Maybe::Value(value) => {
            *target = value.clone();
            Ok(())
        }
    }
}

fn require_project_revision(value: Option<u64>, command: &str) -> Result<(), DomainError> {
    match value {
        Some(revision) if revision > 0 => Ok(()),
        _ => Err(validation(format!(
            "{command} requires a nonzero expected_project_revision"
        ))),
    }
}

fn validate_optional_project_revision(
    value: Option<u64>,
    command: &str,
) -> Result<(), DomainError> {
    if value == Some(0) {
        return Err(validation(format!(
            "{command} expected_project_revision must be absent or nonzero"
        )));
    }
    Ok(())
}

fn validate_patch(patch: &TaskPatch) -> Result<(), DomainError> {
    if let Maybe::Value(value) = &patch.title {
        validate_task_title(value)?;
    }
    if let Maybe::Value(value) = &patch.description {
        validate_description(value)?;
    }
    Ok(())
}

pub fn validate_project_name(value: &str) -> Result<(), DomainError> {
    validate_nonempty_trimmed(value, MAX_PROJECT_NAME_CHARS, "project name")
}

pub fn validate_task_title(value: &str) -> Result<(), DomainError> {
    validate_nonempty_trimmed(value, MAX_TASK_TITLE_CHARS, "task title")
}

pub fn validate_description(value: &str) -> Result<(), DomainError> {
    if value.chars().count() > MAX_TASK_DESCRIPTION_CHARS {
        return Err(validation(format!(
            "task description exceeds {MAX_TASK_DESCRIPTION_CHARS} characters"
        )));
    }
    Ok(())
}

fn validate_nonempty_trimmed(value: &str, max: usize, field: &str) -> Result<(), DomainError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(validation(format!("{field} must not be empty")));
    }
    if trimmed.chars().count() > max {
        return Err(validation(format!("{field} exceeds {max} characters")));
    }
    if trimmed.len() != value.len() {
        return Err(validation(format!(
            "{field} must not have leading or trailing whitespace"
        )));
    }
    Ok(())
}

fn validation(message: impl Into<String>) -> DomainError {
    DomainError::Validation(message.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn task() -> Task {
        let now = Utc::now();
        Task {
            id: Uuid::new_v4(),
            project_id: Uuid::new_v4(),
            title: "Initial".to_owned(),
            description: String::new(),
            status: TaskStatus::Todo,
            priority: TaskPriority::Medium,
            assignee_id: None,
            due_date: None,
            version: 1,
            created_by: Uuid::new_v4(),
            updated_by: Uuid::new_v4(),
            created_at: now,
            updated_at: now,
        }
    }

    #[test]
    fn update_increments_version_and_changes_fields() {
        let actor = Uuid::new_v4();
        let patch = TaskPatch {
            title: Maybe::Value("Changed".to_owned()),
            status: Maybe::Value(TaskStatus::Done),
            ..TaskPatch::default()
        };

        let updated = update_task(&task(), &patch, actor).expect("patch should be valid");

        assert_eq!(updated.title, "Changed");
        assert_eq!(updated.status, TaskStatus::Done);
        assert_eq!(updated.version, 2);
        assert_eq!(updated.updated_by, actor);
    }

    #[test]
    fn null_is_rejected_for_required_fields() {
        let patch = TaskPatch {
            title: Maybe::Null,
            ..TaskPatch::default()
        };

        assert!(matches!(
            update_task(&task(), &patch, Uuid::new_v4()),
            Err(DomainError::Validation(_))
        ));
    }

    #[test]
    fn empty_command_patch_is_rejected() {
        let envelope = CommandEnvelope {
            client_id: Uuid::new_v4(),
            command_id: Uuid::new_v4(),
            project_id: Uuid::new_v4(),
            expected_revision: Some(1),
            command: Command::UpdateTask {
                task_id: Uuid::new_v4(),
                expected_entity_version: 1,
                patch: TaskPatch::default(),
            },
        };

        assert!(matches!(
            envelope.validate(),
            Err(DomainError::Validation(_))
        ));
    }
}
