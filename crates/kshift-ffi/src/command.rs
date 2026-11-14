use chrono::NaiveDate;
use domain::{
    Command, CommandEnvelope, Maybe, ProjectRole, TaskMutation, TaskPatch, TaskPriority, TaskStatus,
};
use kshift_core::PlanCommand;
use serde::Deserialize;
use uuid::Uuid;

use crate::error::FfiError;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CommandEnvelopeDto {
    client_id: String,
    command_id: String,
    project_id: String,
    #[serde(default)]
    expected_project_revision: Option<u64>,
    command: CommandDto,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
enum CommandDto {
    CreateProject(CreateProjectDto),
    AddProjectMember(AddProjectMemberDto),
    CreateTask(CreateTaskDto),
    UpdateTask(UpdateTaskDto),
    DeleteTask(DeleteTaskDto),
    BatchUpdateTasks(BatchUpdateTasksDto),
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct BatchUpdateTasksDto {
    mutations: Vec<TaskMutationDto>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
enum TaskMutationDto {
    #[serde(rename = "create_task")]
    Create(CreateTaskDto),
    #[serde(rename = "update_task")]
    Update(UpdateTaskDto),
    #[serde(rename = "delete_task")]
    Delete(DeleteTaskDto),
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CreateProjectDto {
    name: String,
    time_zone: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct AddProjectMemberDto {
    user_id: String,
    role: ProjectRoleDto,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CreateTaskDto {
    title: String,
    #[serde(default)]
    description_markdown: String,
    status: TaskStatusDto,
    priority: TaskPriorityDto,
    #[serde(default)]
    assignee_ids: Vec<String>,
    planned_on: String,
    #[serde(default)]
    starts_on: Option<String>,
    #[serde(default)]
    due_on: Option<String>,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    parent_task_id: Option<String>,
    #[serde(default)]
    dependency_task_ids: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct UpdateTaskDto {
    task_id: String,
    expected_entity_version: u64,
    #[serde(default)]
    title: PatchField<String>,
    #[serde(default)]
    description_markdown: PatchField<String>,
    #[serde(default)]
    status: PatchField<TaskStatusDto>,
    #[serde(default)]
    priority: PatchField<TaskPriorityDto>,
    #[serde(default)]
    assignee_ids: PatchField<Vec<String>>,
    #[serde(default)]
    planned_on: PatchField<String>,
    #[serde(default)]
    starts_on: PatchField<String>,
    #[serde(default)]
    due_on: PatchField<String>,
    #[serde(default)]
    tags: PatchField<Vec<String>>,
    #[serde(default)]
    parent_task_id: PatchField<String>,
    #[serde(default)]
    dependency_task_ids: PatchField<Vec<String>>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct DeleteTaskDto {
    task_id: String,
    expected_entity_version: u64,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum ProjectRoleDto {
    Viewer,
    Editor,
    Admin,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum TaskStatusDto {
    Todo,
    InProgress,
    Blocked,
    Done,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum TaskPriorityDto {
    None,
    Low,
    Medium,
    High,
    Urgent,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PlanDepthCommandRequestDto {
    request_id: String,
    project_id: String,
    expected_revision: u64,
    command: PlanDepthCommandDto,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
enum PlanDepthCommandDto {
    SetTaskStatus(SetPlanTaskStatusDto),
    Rollback(RollbackPlanDto),
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SetPlanTaskStatusDto {
    task_id: String,
    status: TaskStatusDto,
    expected_version: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RollbackPlanDto {
    target_revision: u64,
    reason: String,
}

#[derive(Clone, Debug, Default)]
enum PatchField<T> {
    #[default]
    Unset,
    Null,
    Value(T),
}

impl<'de, T> Deserialize<'de> for PatchField<T>
where
    T: Deserialize<'de>,
{
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        Ok(Option::<T>::deserialize(deserializer)?.map_or(Self::Null, Self::Value))
    }
}

pub fn command_from_json(bytes: &[u8]) -> Result<CommandEnvelope, FfiError> {
    let dto: CommandEnvelopeDto = serde_json::from_slice(bytes)
        .map_err(|error| FfiError::InvalidArgument(format!("invalid command JSON: {error}")))?;
    let command = match dto.command {
        CommandDto::CreateProject(value) => Command::CreateProject {
            name: value.name,
            time_zone: value.time_zone,
        },
        CommandDto::AddProjectMember(value) => Command::AddProjectMember {
            user_id: parse_uuid("user_id", &value.user_id)?,
            role: project_role(value.role),
        },
        CommandDto::CreateTask(value) => Command::CreateTask {
            task_id: Uuid::new_v4(),
            title: value.title,
            description_markdown: value.description_markdown,
            status: task_status(value.status),
            priority: task_priority(value.priority),
            assignee_ids: parse_uuid_list("assignee_ids", value.assignee_ids)?,
            planned_on: parse_date("planned_on", &value.planned_on)?,
            starts_on: value
                .starts_on
                .as_deref()
                .map(|value| parse_date("starts_on", value))
                .transpose()?,
            due_on: value
                .due_on
                .as_deref()
                .map(|value| parse_date("due_on", value))
                .transpose()?,
            tags: value.tags,
            parent_task_id: value
                .parent_task_id
                .as_deref()
                .map(|value| parse_uuid("parent_task_id", value))
                .transpose()?,
            dependency_task_ids: parse_uuid_list("dependency_task_ids", value.dependency_task_ids)?,
        },
        CommandDto::UpdateTask(value) => Command::UpdateTask {
            task_id: parse_uuid("task_id", &value.task_id)?,
            expected_entity_version: value.expected_entity_version,
            patch: task_patch(value)?,
        },
        CommandDto::DeleteTask(value) => Command::DeleteTask {
            task_id: parse_uuid("task_id", &value.task_id)?,
            expected_entity_version: value.expected_entity_version,
        },
        CommandDto::BatchUpdateTasks(value) => Command::BatchUpdateTasks {
            mutations: value
                .mutations
                .into_iter()
                .map(task_mutation)
                .collect::<Result<Vec<_>, _>>()?,
        },
    };
    let envelope = CommandEnvelope {
        client_id: parse_uuid("client_id", &dto.client_id)?,
        command_id: parse_uuid("command_id", &dto.command_id)?,
        project_id: parse_uuid("project_id", &dto.project_id)?,
        expected_revision: dto.expected_project_revision,
        command,
    };
    envelope.validate()?;
    Ok(envelope)
}

pub fn plan_depth_command_from_json(
    bytes: &[u8],
) -> Result<contract::PlanDepthCommandInput, FfiError> {
    let dto: PlanDepthCommandRequestDto = serde_json::from_slice(bytes)
        .map_err(|error| FfiError::InvalidArgument(format!("invalid R3 command JSON: {error}")))?;
    let command = match dto.command {
        PlanDepthCommandDto::SetTaskStatus(value) => PlanCommand::SetTaskStatus {
            task_id: parse_uuid("task_id", &value.task_id)?.to_string(),
            status: plan_task_status(value.status),
            expected_version: value.expected_version,
        },
        PlanDepthCommandDto::Rollback(value) => PlanCommand::Rollback {
            target_revision: value.target_revision,
            reason: value.reason,
        },
    };
    Ok(contract::PlanDepthCommandInput {
        request_id: parse_uuid("request_id", &dto.request_id)?,
        project_id: parse_uuid("project_id", &dto.project_id)?,
        expected_revision: dto.expected_revision,
        command,
    })
}

fn task_mutation(value: TaskMutationDto) -> Result<TaskMutation, FfiError> {
    match value {
        TaskMutationDto::Create(value) => {
            let task_id = Uuid::new_v4();
            Ok(TaskMutation::CreateTask {
                task_id,
                title: value.title,
                description_markdown: value.description_markdown,
                status: task_status(value.status),
                priority: task_priority(value.priority),
                assignee_ids: parse_uuid_list("assignee_ids", value.assignee_ids)?,
                planned_on: parse_date("planned_on", &value.planned_on)?,
                starts_on: value
                    .starts_on
                    .as_deref()
                    .map(|value| parse_date("starts_on", value))
                    .transpose()?,
                due_on: value
                    .due_on
                    .as_deref()
                    .map(|value| parse_date("due_on", value))
                    .transpose()?,
                tags: value.tags,
                parent_task_id: value
                    .parent_task_id
                    .as_deref()
                    .map(|value| parse_uuid("parent_task_id", value))
                    .transpose()?,
                dependency_task_ids: parse_uuid_list(
                    "dependency_task_ids",
                    value.dependency_task_ids,
                )?,
            })
        }
        TaskMutationDto::Update(value) => Ok(TaskMutation::UpdateTask {
            task_id: parse_uuid("task_id", &value.task_id)?,
            expected_entity_version: value.expected_entity_version,
            patch: task_patch(value)?,
        }),
        TaskMutationDto::Delete(value) => Ok(TaskMutation::DeleteTask {
            task_id: parse_uuid("task_id", &value.task_id)?,
            expected_entity_version: value.expected_entity_version,
        }),
    }
}

fn task_patch(value: UpdateTaskDto) -> Result<TaskPatch, FfiError> {
    Ok(TaskPatch {
        title: maybe_scalar(value.title, |value| value),
        description_markdown: maybe_scalar(value.description_markdown, |value| value),
        status: maybe_scalar(value.status, task_status),
        priority: maybe_scalar(value.priority, task_priority),
        assignee_ids: maybe_uuid_list("assignee_ids", value.assignee_ids)?,
        planned_on: maybe_date("planned_on", value.planned_on)?,
        starts_on: maybe_optional_date("starts_on", value.starts_on)?,
        due_on: maybe_optional_date("due_on", value.due_on)?,
        tags: maybe_string_list(value.tags),
        parent_task_id: maybe_optional_uuid("parent_task_id", value.parent_task_id)?,
        dependency_task_ids: maybe_uuid_list("dependency_task_ids", value.dependency_task_ids)?,
    })
}

fn maybe_scalar<T, U>(value: PatchField<T>, map: impl FnOnce(T) -> U) -> Maybe<U> {
    match value {
        PatchField::Unset => Maybe::Unset,
        PatchField::Null => Maybe::Null,
        PatchField::Value(value) => Maybe::Value(map(value)),
    }
}

fn maybe_uuid_list(
    field: &'static str,
    value: PatchField<Vec<String>>,
) -> Result<Maybe<Vec<Uuid>>, FfiError> {
    match value {
        PatchField::Unset => Ok(Maybe::Unset),
        PatchField::Null => Ok(Maybe::Null),
        PatchField::Value(values) => Ok(Maybe::Value(parse_uuid_list(field, values)?)),
    }
}

fn maybe_string_list(value: PatchField<Vec<String>>) -> Maybe<Vec<String>> {
    maybe_scalar(value, |values| values)
}

fn maybe_date(
    field: &'static str,
    value: PatchField<String>,
) -> Result<Maybe<NaiveDate>, FfiError> {
    match value {
        PatchField::Unset => Ok(Maybe::Unset),
        PatchField::Null => Ok(Maybe::Null),
        PatchField::Value(value) => Ok(Maybe::Value(parse_date(field, &value)?)),
    }
}

fn maybe_optional_date(
    field: &'static str,
    value: PatchField<String>,
) -> Result<Maybe<Option<NaiveDate>>, FfiError> {
    match value {
        PatchField::Unset => Ok(Maybe::Unset),
        PatchField::Null => Ok(Maybe::Null),
        PatchField::Value(value) if value.is_empty() => Ok(Maybe::Null),
        PatchField::Value(value) => Ok(Maybe::Value(Some(parse_date(field, &value)?))),
    }
}

fn maybe_optional_uuid(
    field: &'static str,
    value: PatchField<String>,
) -> Result<Maybe<Option<Uuid>>, FfiError> {
    match value {
        PatchField::Unset => Ok(Maybe::Unset),
        PatchField::Null => Ok(Maybe::Null),
        PatchField::Value(value) if value.is_empty() => Ok(Maybe::Null),
        PatchField::Value(value) => Ok(Maybe::Value(Some(parse_uuid(field, &value)?))),
    }
}

fn parse_uuid_list(field: &'static str, values: Vec<String>) -> Result<Vec<Uuid>, FfiError> {
    values
        .iter()
        .map(|value| parse_uuid(field, value))
        .collect()
}

fn parse_uuid(field: &'static str, value: &str) -> Result<Uuid, FfiError> {
    Uuid::parse_str(value).map_err(|_| FfiError::InvalidArgument(format!("{field} must be a UUID")))
}

fn parse_date(field: &'static str, value: &str) -> Result<NaiveDate, FfiError> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| FfiError::InvalidArgument(format!("{field} must use YYYY-MM-DD")))
}

fn project_role(value: ProjectRoleDto) -> ProjectRole {
    match value {
        ProjectRoleDto::Viewer => ProjectRole::Viewer,
        ProjectRoleDto::Editor => ProjectRole::Editor,
        ProjectRoleDto::Admin => ProjectRole::Admin,
    }
}

fn task_status(value: TaskStatusDto) -> TaskStatus {
    match value {
        TaskStatusDto::Todo => TaskStatus::Todo,
        TaskStatusDto::InProgress => TaskStatus::InProgress,
        TaskStatusDto::Blocked => TaskStatus::Blocked,
        TaskStatusDto::Done => TaskStatus::Done,
    }
}

fn plan_task_status(value: TaskStatusDto) -> kshift_core::TaskStatus {
    match value {
        TaskStatusDto::Todo => kshift_core::TaskStatus::Todo,
        TaskStatusDto::InProgress => kshift_core::TaskStatus::InProgress,
        TaskStatusDto::Blocked => kshift_core::TaskStatus::Blocked,
        TaskStatusDto::Done => kshift_core::TaskStatus::Done,
    }
}

fn task_priority(value: TaskPriorityDto) -> TaskPriority {
    match value {
        TaskPriorityDto::None => TaskPriority::None,
        TaskPriorityDto::Low => TaskPriority::Low,
        TaskPriorityDto::Medium => TaskPriority::Medium,
        TaskPriorityDto::High => TaskPriority::High,
        TaskPriorityDto::Urgent => TaskPriority::Urgent,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_atomic_batch_update() {
        let json = br#"{
          "client_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
          "command_id": "99999999-8888-4777-8666-555555555555",
          "project_id": "11111111-2222-4333-8444-555555555555",
          "expected_project_revision": 7,
          "command": {
            "type": "batch_update_tasks",
            "value": {
              "mutations": [
                {
                  "type": "update_task",
                  "value": {
                    "task_id": "22222222-2222-4222-8222-222222222222",
                    "expected_entity_version": 3,
                    "status": "done"
                  }
                },
                {
                  "type": "update_task",
                  "value": {
                    "task_id": "33333333-3333-4333-8333-333333333333",
                    "expected_entity_version": 4,
                    "status": "done"
                  }
                }
              ]
            }
          }
        }"#;
        let envelope = command_from_json(json).expect("batch JSON should parse");
        let Command::BatchUpdateTasks { mutations } = envelope.command else {
            panic!("expected batch command");
        };
        assert_eq!(mutations.len(), 2);
        assert!(matches!(
            &mutations[0],
            TaskMutation::UpdateTask {
                expected_entity_version: 3,
                patch: TaskPatch {
                    status: Maybe::Value(TaskStatus::Done),
                    ..
                },
                ..
            }
        ));
    }

    #[test]
    fn parses_r3_status_command() {
        let json = br#"{
          "request_id": "99999999-8888-4777-8666-555555555555",
          "project_id": "11111111-2222-4333-8444-555555555555",
          "expected_revision": 7,
          "command": {
            "type": "set_task_status",
            "value": {
              "task_id": "22222222-2222-4222-8222-222222222222",
              "status": "done",
              "expected_version": 3
            }
          }
        }"#;
        let input = plan_depth_command_from_json(json).expect("R3 command should parse");
        assert_eq!(input.expected_revision, 7);
        assert!(matches!(
            input.command,
            PlanCommand::SetTaskStatus {
                status: kshift_core::TaskStatus::Done,
                expected_version: 3,
                ..
            }
        ));
    }
}
