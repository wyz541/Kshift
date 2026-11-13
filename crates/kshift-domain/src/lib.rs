//! Pure Kshift business types and invariants. This crate performs no I/O.

use std::str::FromStr;

use chrono::{DateTime, NaiveDate, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

pub const SCHEMA_VERSION: u32 = 1;
pub const MAX_PROJECT_NAME_CHARS: usize = 120;
pub const MAX_TIME_ZONE_CHARS: usize = 64;
pub const MAX_TASK_TITLE_CHARS: usize = 200;
pub const MAX_TASK_DESCRIPTION_CHARS: usize = 20_000;
pub const MAX_ASSIGNEES: usize = 20;
pub const MAX_TAGS: usize = 30;
pub const MAX_TAG_CHARS: usize = 32;
pub const MAX_DEPENDENCIES: usize = 50;
pub const MAX_BATCH_MUTATIONS: usize = 100;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProjectRole {
    Viewer,
    Editor,
    Admin,
}

impl ProjectRole {
    pub fn can_read(self) -> bool {
        true
    }

    pub fn can_write(self) -> bool {
        matches!(self, Self::Editor | Self::Admin)
    }

    pub fn can_manage_members(self) -> bool {
        matches!(self, Self::Admin)
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
    None,
    Low,
    Medium,
    High,
    Urgent,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Project {
    pub id: Uuid,
    pub name: String,
    pub time_zone: String,
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
    pub description_markdown: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub assignee_ids: Vec<Uuid>,
    pub planned_on: NaiveDate,
    pub starts_on: Option<NaiveDate>,
    pub due_on: Option<NaiveDate>,
    pub tags: Vec<String>,
    pub parent_task_id: Option<Uuid>,
    pub dependency_task_ids: Vec<Uuid>,
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
    pub description_markdown: Maybe<String>,
    pub status: Maybe<TaskStatus>,
    pub priority: Maybe<TaskPriority>,
    pub assignee_ids: Maybe<Vec<Uuid>>,
    pub planned_on: Maybe<NaiveDate>,
    pub starts_on: Maybe<Option<NaiveDate>>,
    pub due_on: Maybe<Option<NaiveDate>>,
    pub tags: Maybe<Vec<String>>,
    pub parent_task_id: Maybe<Option<Uuid>>,
    pub dependency_task_ids: Maybe<Vec<Uuid>>,
}

impl TaskPatch {
    pub fn is_empty(&self) -> bool {
        matches!(self.title, Maybe::Unset)
            && matches!(self.description_markdown, Maybe::Unset)
            && matches!(self.status, Maybe::Unset)
            && matches!(self.priority, Maybe::Unset)
            && matches!(self.assignee_ids, Maybe::Unset)
            && matches!(self.planned_on, Maybe::Unset)
            && matches!(self.starts_on, Maybe::Unset)
            && matches!(self.due_on, Maybe::Unset)
            && matches!(self.tags, Maybe::Unset)
            && matches!(self.parent_task_id, Maybe::Unset)
            && matches!(self.dependency_task_ids, Maybe::Unset)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Command {
    CreateProject {
        name: String,
        time_zone: String,
    },
    AddProjectMember {
        user_id: Uuid,
        role: ProjectRole,
    },
    CreateTask {
        task_id: Uuid,
        title: String,
        description_markdown: String,
        status: TaskStatus,
        priority: TaskPriority,
        assignee_ids: Vec<Uuid>,
        planned_on: NaiveDate,
        starts_on: Option<NaiveDate>,
        due_on: Option<NaiveDate>,
        tags: Vec<String>,
        parent_task_id: Option<Uuid>,
        dependency_task_ids: Vec<Uuid>,
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
    BatchUpdateTasks {
        mutations: Vec<TaskMutation>,
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
            Self::BatchUpdateTasks { .. } => "batch_update_tasks",
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
            Command::CreateProject { name, time_zone } => {
                if !matches!(self.expected_revision, None | Some(0)) {
                    return Err(validation(
                        "create_project expected_project_revision must be absent or 0",
                    ));
                }
                validate_project_name(name)?;
                validate_time_zone(time_zone)
            }
            Command::AddProjectMember { .. } => {
                require_project_revision(self.expected_revision, "add_project_member")
            }
            Command::CreateTask {
                task_id,
                title,
                description_markdown,
                assignee_ids,
                planned_on,
                starts_on,
                due_on,
                tags,
                parent_task_id,
                dependency_task_ids,
                ..
            } => {
                require_project_revision(self.expected_revision, "create_task")?;
                validate_task_title(title)?;
                validate_description(description_markdown)?;
                validate_finite_date(*planned_on, starts_on, due_on)?;
                validate_collection_invariants(
                    task_id,
                    assignee_ids,
                    tags,
                    parent_task_id,
                    dependency_task_ids,
                )
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
            Command::BatchUpdateTasks { mutations } => {
                require_project_revision(self.expected_revision, "batch_update_tasks")?;
                validate_batch_mutations(mutations)
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
pub enum TaskMutation {
    CreateTask {
        task_id: Uuid,
        title: String,
        description_markdown: String,
        status: TaskStatus,
        priority: TaskPriority,
        assignee_ids: Vec<Uuid>,
        planned_on: NaiveDate,
        starts_on: Option<NaiveDate>,
        due_on: Option<NaiveDate>,
        tags: Vec<String>,
        parent_task_id: Option<Uuid>,
        dependency_task_ids: Vec<Uuid>,
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

impl TaskMutation {
    fn task_id(&self) -> Uuid {
        match self {
            Self::CreateTask { task_id, .. }
            | Self::UpdateTask { task_id, .. }
            | Self::DeleteTask { task_id, .. } => *task_id,
        }
    }
}

fn validate_batch_mutations(mutations: &[TaskMutation]) -> Result<(), DomainError> {
    if mutations.is_empty() {
        return Err(validation(
            "batch_update_tasks must contain at least one mutation",
        ));
    }
    if mutations.len() > MAX_BATCH_MUTATIONS {
        return Err(validation(format!(
            "batch_update_tasks must contain at most {MAX_BATCH_MUTATIONS} mutations"
        )));
    }
    let mut seen = std::collections::HashSet::with_capacity(mutations.len());
    for mutation in mutations {
        let task_id = mutation.task_id();
        if task_id.is_nil() {
            return Err(validation("batch_update_tasks task_id must not be nil"));
        }
        if !seen.insert(task_id) {
            return Err(validation(
                "batch_update_tasks must not mutate the same task twice",
            ));
        }
        match mutation {
            TaskMutation::CreateTask {
                task_id,
                title,
                description_markdown,
                assignee_ids,
                planned_on,
                starts_on,
                due_on,
                tags,
                parent_task_id,
                dependency_task_ids,
                ..
            } => {
                validate_task_title(title)?;
                validate_description(description_markdown)?;
                validate_finite_date(*planned_on, starts_on, due_on)?;
                validate_collection_invariants(
                    task_id,
                    assignee_ids,
                    tags,
                    parent_task_id,
                    dependency_task_ids,
                )?;
            }
            TaskMutation::UpdateTask {
                expected_entity_version,
                patch,
                ..
            } => {
                if *expected_entity_version == 0 {
                    return Err(validation(
                        "batch_update_tasks entity version must be nonzero",
                    ));
                }
                if patch.is_empty() {
                    return Err(validation(
                        "batch_update_tasks patch must contain at least one field",
                    ));
                }
                validate_patch(patch)?;
            }
            TaskMutation::DeleteTask {
                expected_entity_version,
                ..
            } => {
                if *expected_entity_version == 0 {
                    return Err(validation(
                        "batch_update_tasks entity version must be nonzero",
                    ));
                }
            }
        }
    }
    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Change {
    ProjectUpserted { project: Project },
    ProjectMemberUpserted { member: ProjectMember },
    TaskCreated { task: Task },
    TaskUpdated { task: Task },
    TaskDeleted { task_id: Uuid },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChangeEvent {
    pub project_id: Uuid,
    pub revision: u64,
    pub schema_version: u32,
    pub command_id: Uuid,
    pub occurred_at: DateTime<Utc>,
    pub changes: Vec<Change>,
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
    #[error("{0}")]
    Unsupported(String),
}

pub fn update_task(task: &Task, patch: &TaskPatch, actor_id: Uuid) -> Result<Task, DomainError> {
    validate_patch(patch)?;
    let mut next = task.clone();
    apply_maybe(&mut next.title, &patch.title, |value| {
        validate_task_title(value)
    })?;
    apply_maybe(
        &mut next.description_markdown,
        &patch.description_markdown,
        |value| validate_description(value),
    )?;
    apply_maybe(&mut next.status, &patch.status, |_| Ok(()))?;
    apply_maybe(&mut next.priority, &patch.priority, |_| Ok(()))?;
    apply_maybe(&mut next.assignee_ids, &patch.assignee_ids, |_| Ok(()))?;
    apply_maybe(&mut next.planned_on, &patch.planned_on, |_| Ok(()))?;
    apply_optional(&mut next.starts_on, &patch.starts_on)?;
    apply_optional(&mut next.due_on, &patch.due_on)?;
    apply_maybe(&mut next.tags, &patch.tags, |_| Ok(()))?;
    apply_optional(&mut next.parent_task_id, &patch.parent_task_id)?;
    apply_maybe(
        &mut next.dependency_task_ids,
        &patch.dependency_task_ids,
        |_| Ok(()),
    )?;
    validate_finite_date(next.planned_on, &next.starts_on, &next.due_on)?;
    validate_collection_invariants(
        &next.id,
        &next.assignee_ids,
        &next.tags,
        &next.parent_task_id,
        &next.dependency_task_ids,
    )?;
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
    if let Maybe::Value(value) = &patch.description_markdown {
        validate_description(value)?;
    }
    if let Maybe::Value(value) = &patch.tags {
        validate_tags(value)?;
    }
    if let Maybe::Value(value) = &patch.assignee_ids {
        validate_assignee_ids(value)?;
    }
    if let Maybe::Value(value) = &patch.dependency_task_ids {
        validate_dependencies(value, None)?;
    }
    Ok(())
}

pub fn validate_project_name(value: &str) -> Result<(), DomainError> {
    validate_nonempty_trimmed(value, MAX_PROJECT_NAME_CHARS, "project name")
}

pub fn validate_time_zone(value: &str) -> Result<(), DomainError> {
    if value.is_empty() || value.chars().count() > MAX_TIME_ZONE_CHARS {
        return Err(validation("time_zone must contain 1 to 64 characters"));
    }
    Tz::from_str(value).map_err(|_| validation("time_zone must be a valid IANA time zone"))?;
    Ok(())
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

fn validate_finite_date(
    planned_on: NaiveDate,
    starts_on: &Option<NaiveDate>,
    due_on: &Option<NaiveDate>,
) -> Result<(), DomainError> {
    if matches!(starts_on, Some(date) if *date > planned_on) {
        return Err(validation("starts_on must not be after planned_on"));
    }
    if matches!(due_on, Some(date) if *date < planned_on) {
        return Err(validation("due_on must not be before planned_on"));
    }
    if let (Some(starts_on), Some(due_on)) = (starts_on, due_on) {
        if due_on < starts_on {
            return Err(validation("due_on must not be before starts_on"));
        }
    }
    Ok(())
}

fn validate_collection_invariants(
    task_id: &Uuid,
    assignee_ids: &[Uuid],
    tags: &[String],
    parent_task_id: &Option<Uuid>,
    dependency_task_ids: &[Uuid],
) -> Result<(), DomainError> {
    validate_assignee_ids(assignee_ids)?;
    validate_tags(tags)?;
    validate_dependencies(dependency_task_ids, Some(task_id))?;
    if parent_task_id.as_ref() == Some(task_id) {
        return Err(validation(
            "parent_task_id must not reference the task itself",
        ));
    }
    Ok(())
}

fn validate_assignee_ids(values: &[Uuid]) -> Result<(), DomainError> {
    if values.len() > MAX_ASSIGNEES {
        return Err(validation(format!(
            "assignee_ids must contain at most {MAX_ASSIGNEES} users"
        )));
    }
    validate_unique_ids(values, "assignee_ids")
}

fn validate_dependencies(values: &[Uuid], task_id: Option<&Uuid>) -> Result<(), DomainError> {
    if values.len() > MAX_DEPENDENCIES {
        return Err(validation(format!(
            "dependency_task_ids must contain at most {MAX_DEPENDENCIES} tasks"
        )));
    }
    if values.iter().any(Uuid::is_nil) {
        return Err(validation("dependency_task_ids must not contain nil UUIDs"));
    }
    if task_id.is_some_and(|task_id| values.contains(task_id)) {
        return Err(validation(
            "dependency_task_ids must not reference the task itself",
        ));
    }
    validate_unique_ids(values, "dependency_task_ids")
}

fn validate_unique_ids(values: &[Uuid], field: &str) -> Result<(), DomainError> {
    if values.iter().any(Uuid::is_nil) {
        return Err(validation(format!("{field} must not contain nil UUIDs")));
    }
    let mut sorted = values.to_vec();
    sorted.sort_unstable();
    sorted.dedup();
    if sorted.len() != values.len() {
        return Err(validation(format!("{field} must not contain duplicates")));
    }
    Ok(())
}

fn validate_tags(values: &[String]) -> Result<(), DomainError> {
    if values.len() > MAX_TAGS {
        return Err(validation(format!(
            "tags must contain at most {MAX_TAGS} values"
        )));
    }
    let mut seen = std::collections::HashSet::with_capacity(values.len());
    for tag in values {
        validate_nonempty_trimmed(tag, MAX_TAG_CHARS, "tag")?;
        if !seen.insert(tag.as_str()) {
            return Err(validation("tags must not contain duplicates"));
        }
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
            description_markdown: String::new(),
            status: TaskStatus::Todo,
            priority: TaskPriority::Medium,
            assignee_ids: Vec::new(),
            planned_on: NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
            starts_on: None,
            due_on: None,
            tags: Vec::new(),
            parent_task_id: None,
            dependency_task_ids: Vec::new(),
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

    #[test]
    fn dependency_cannot_reference_itself() {
        let task = task();
        let patch = TaskPatch {
            dependency_task_ids: Maybe::Value(vec![task.id]),
            ..TaskPatch::default()
        };

        assert!(matches!(
            update_task(&task, &patch, Uuid::new_v4()),
            Err(DomainError::Validation(_))
        ));
    }
}
