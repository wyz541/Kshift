use std::collections::BTreeMap;

use chrono::NaiveDate;
use kshift_core::{
    AttachmentLink, AttachmentMetadata, PlanActorRole, PlanCommand, PlanCommandResponse,
    PlanDepthSnapshot, PlanError, PlanHistoryEntry, PlanProject, PlanStatistics, PlanTask,
    ReportRange, ReportTask, TaskDependency, TaskPriority, TaskStatus, WorkReport,
};
use uuid::Uuid;

use crate::{v1, ApiError};

/// Validated R3 command before the server attaches actor identity.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlanDepthCommandInput {
    /// Stable request identity used for retry tracking.
    pub request_id: Uuid,
    /// Project that owns the command.
    pub project_id: Uuid,
    /// Snapshot revision that the caller observed.
    pub expected_revision: u64,
    /// Typed R3 command.
    pub command: PlanCommand,
}

/// Parse one R3 command request without trusting client actor fields.
pub fn parse_execute_plan_depth_command(
    request: &v1::ExecutePlanDepthCommandRequest,
) -> Result<PlanDepthCommandInput, ApiError> {
    let request_id = parse_uuid(&request.request_id, "request_id")?;
    let project_id = parse_uuid(&request.project_id, "project_id")?;
    let command = parse_plan_command(request.command.as_ref())?;
    Ok(PlanDepthCommandInput {
        request_id,
        project_id,
        expected_revision: request.expected_revision,
        command,
    })
}

/// Build one wire R3 command request from a validated input.
pub fn plan_depth_command_to_proto(
    input: &PlanDepthCommandInput,
) -> Result<v1::ExecutePlanDepthCommandRequest, ApiError> {
    let command = match &input.command {
        PlanCommand::SetTaskStatus {
            task_id,
            status,
            expected_version,
        } => v1::plan_command::Command::SetTaskStatus(v1::SetPlanTaskStatusCommand {
            task_id: parse_required_uuid_string(task_id, "task_id")?,
            status: task_status_to_proto(*status) as i32,
            expected_version: *expected_version,
        }),
        PlanCommand::Rollback {
            target_revision,
            reason,
        } => v1::plan_command::Command::Rollback(v1::RollbackPlanCommand {
            target_revision: *target_revision,
            reason: reason.clone(),
        }),
        _ => {
            return Err(ApiError::Unsupported(
                "R3 boundary currently supports status and rollback commands".to_owned(),
            ))
        }
    };
    Ok(v1::ExecutePlanDepthCommandRequest {
        request_id: input.request_id.to_string(),
        project_id: input.project_id.to_string(),
        expected_revision: input.expected_revision,
        command: Some(v1::PlanCommand {
            command: Some(command),
        }),
    })
}

fn parse_plan_command(command: Option<&v1::PlanCommand>) -> Result<PlanCommand, ApiError> {
    let command = command
        .and_then(|value| value.command.as_ref())
        .ok_or_else(|| ApiError::InvalidArgument("command is required".to_owned()))?;
    match command {
        v1::plan_command::Command::SetTaskStatus(value) => Ok(PlanCommand::SetTaskStatus {
            task_id: value.task_id.clone(),
            status: task_status_from_proto(value.status)?,
            expected_version: value.expected_version,
        }),
        v1::plan_command::Command::Rollback(value) => Ok(PlanCommand::Rollback {
            target_revision: value.target_revision,
            reason: value.reason.clone(),
        }),
    }
}

/// Convert one R3 snapshot into its stable protobuf projection.
pub fn plan_depth_snapshot_to_proto(value: &PlanDepthSnapshot) -> v1::PlanDepthSnapshot {
    v1::PlanDepthSnapshot {
        project: Some(v1::PlanProject {
            id: value.project.id.clone(),
            name: value.project.name.clone(),
            revision: value.project.revision,
            schema_version: value.project.schema_version,
        }),
        people: value
            .people
            .iter()
            .map(|person| v1::PlanPerson {
                id: person.id.clone(),
                name: person.name.clone(),
                initials: person.initials.clone(),
                color_hex: person.color_hex.clone(),
            })
            .collect(),
        tasks: value
            .tasks
            .iter()
            .map(|task| v1::PlanTask {
                id: task.id.clone(),
                project_id: task.project_id.clone(),
                parent_id: task.parent_id.clone(),
                title: task.title.clone(),
                description_markdown: task.description_markdown.clone(),
                status: task_status_to_proto(task.status) as i32,
                priority: task_priority_to_proto(task.priority) as i32,
                assignee_id: task.assignee_id.clone(),
                starts_on: task.starts_on.to_string(),
                due_on: task.due_on.to_string(),
                estimate_minutes: task.estimate_minutes,
                position: task.position,
                version: task.version,
                completed_at: task.completed_at.clone(),
            })
            .collect(),
        dependencies: value
            .dependencies
            .iter()
            .map(|dependency| v1::PlanTaskDependency {
                task_id: dependency.task_id.clone(),
                depends_on_task_id: dependency.depends_on_task_id.clone(),
            })
            .collect(),
        attachments: value
            .attachments
            .iter()
            .map(|attachment| v1::PlanAttachment {
                id: attachment.id.clone(),
                sha256: attachment.sha256.clone(),
                media_type: attachment.media_type.clone(),
                byte_size: attachment.byte_size,
                filename: attachment.filename.clone(),
            })
            .collect(),
        attachment_links: value
            .attachment_links
            .iter()
            .map(|link| v1::PlanAttachmentLink {
                attachment_id: link.attachment_id.clone(),
                task_id: link.task_id.clone(),
            })
            .collect(),
        history: value
            .history
            .iter()
            .map(|entry| v1::PlanHistoryEntry {
                id: entry.id.clone(),
                revision: entry.revision,
                actor_id: entry.actor_id.clone(),
                action: entry.action.clone(),
                summary: entry.summary.clone(),
                occurred_at: entry.occurred_at.clone(),
                restored_from_revision: entry.restored_from_revision,
                content_sha256: entry.content_sha256.clone(),
            })
            .collect(),
    }
}

/// Decode one R3 snapshot from protobuf.
pub fn plan_depth_snapshot_from_proto(
    value: v1::PlanDepthSnapshot,
) -> Result<PlanDepthSnapshot, ApiError> {
    let project = value
        .project
        .ok_or_else(|| ApiError::InvalidArgument("snapshot.project is required".to_owned()))?;
    Ok(PlanDepthSnapshot {
        project: PlanProject {
            id: project.id,
            name: project.name,
            revision: project.revision,
            schema_version: project.schema_version,
        },
        people: value
            .people
            .into_iter()
            .map(|person| kshift_core::Person {
                id: person.id,
                name: person.name,
                initials: person.initials,
                color_hex: person.color_hex,
            })
            .collect(),
        tasks: value
            .tasks
            .into_iter()
            .map(plan_task_from_proto)
            .collect::<Result<Vec<_>, _>>()?,
        dependencies: value
            .dependencies
            .into_iter()
            .map(|dependency| TaskDependency {
                task_id: dependency.task_id,
                depends_on_task_id: dependency.depends_on_task_id,
            })
            .collect(),
        attachments: value
            .attachments
            .into_iter()
            .map(|attachment| AttachmentMetadata {
                id: attachment.id,
                sha256: attachment.sha256,
                media_type: attachment.media_type,
                byte_size: attachment.byte_size,
                filename: attachment.filename,
            })
            .collect(),
        attachment_links: value
            .attachment_links
            .into_iter()
            .map(|link| AttachmentLink {
                attachment_id: link.attachment_id,
                task_id: link.task_id,
            })
            .collect(),
        history: value
            .history
            .into_iter()
            .map(|entry| PlanHistoryEntry {
                id: entry.id,
                revision: entry.revision,
                actor_id: entry.actor_id,
                action: entry.action,
                summary: entry.summary,
                occurred_at: entry.occurred_at,
                restored_from_revision: entry.restored_from_revision,
                content_sha256: entry.content_sha256,
            })
            .collect(),
    })
}

fn plan_task_from_proto(value: v1::PlanTask) -> Result<PlanTask, ApiError> {
    Ok(PlanTask {
        id: value.id,
        project_id: value.project_id,
        parent_id: value.parent_id,
        title: value.title,
        description_markdown: value.description_markdown,
        status: task_status_from_proto(value.status)?,
        priority: task_priority_from_proto(value.priority)?,
        assignee_id: value.assignee_id,
        starts_on: parse_date(&value.starts_on, "task.starts_on")?,
        due_on: parse_date(&value.due_on, "task.due_on")?,
        estimate_minutes: value.estimate_minutes,
        position: value.position,
        version: value.version,
        completed_at: value.completed_at,
    })
}

/// Convert one certifying command response into its wire projection.
pub fn plan_command_response_to_proto(
    response: &PlanCommandResponse,
    actor_role: PlanActorRole,
) -> v1::ExecutePlanDepthCommandResponse {
    v1::ExecutePlanDepthCommandResponse {
        snapshot: Some(plan_depth_snapshot_to_proto(&response.snapshot)),
        actor_role: plan_actor_role_to_proto(actor_role) as i32,
    }
}

/// Convert one report into protobuf.
pub fn plan_report_to_proto(value: &WorkReport) -> v1::PlanWorkReport {
    v1::PlanWorkReport {
        source_revision: value.source_revision,
        generated_at: value.generated_at.clone(),
        range: Some(v1::PlanReportRange {
            starts_on: value.range.starts_on.to_string(),
            ends_on: value.range.ends_on.to_string(),
        }),
        tasks: value
            .tasks
            .iter()
            .map(|task| v1::PlanReportTask {
                id: task.id.clone(),
                title: task.title.clone(),
                parent_title: task.parent_title.clone(),
                status: task_status_to_proto(task.status) as i32,
                priority: task_priority_to_proto(task.priority) as i32,
                assignee_name: task.assignee_name.clone(),
                starts_on: task.starts_on.to_string(),
                due_on: task.due_on.to_string(),
                estimate_minutes: task.estimate_minutes,
                cross_day: task.cross_day,
                overdue: task.overdue,
                dependency_count: task.dependency_count,
                subtask_count: task.subtask_count,
                attachment_count: task.attachment_count,
            })
            .collect(),
        statistics: Some(v1::PlanReportStatistics {
            task_count: value.statistics.task_count,
            completed_count: value.statistics.completed_count,
            overdue_count: value.statistics.overdue_count,
            cross_day_count: value.statistics.cross_day_count,
            total_estimate_minutes: value.statistics.total_estimate_minutes,
        }),
    }
}

/// Decode one report from protobuf.
pub fn plan_report_from_proto(value: v1::PlanWorkReport) -> Result<WorkReport, ApiError> {
    let range = value
        .range
        .ok_or_else(|| ApiError::InvalidArgument("report.range is required".to_owned()))?;
    let statistics = value.statistics.unwrap_or_default();
    Ok(WorkReport {
        source_revision: value.source_revision,
        generated_at: value.generated_at,
        range: ReportRange {
            starts_on: parse_date(&range.starts_on, "report.range.starts_on")?,
            ends_on: parse_date(&range.ends_on, "report.range.ends_on")?,
        },
        tasks: value
            .tasks
            .into_iter()
            .map(|task| {
                Ok(ReportTask {
                    id: task.id,
                    title: task.title,
                    parent_title: task.parent_title,
                    status: task_status_from_proto(task.status)?,
                    priority: task_priority_from_proto(task.priority)?,
                    assignee_name: task.assignee_name,
                    starts_on: parse_date(&task.starts_on, "report.task.starts_on")?,
                    due_on: parse_date(&task.due_on, "report.task.due_on")?,
                    estimate_minutes: task.estimate_minutes,
                    cross_day: task.cross_day,
                    overdue: task.overdue,
                    dependency_count: task.dependency_count,
                    subtask_count: task.subtask_count,
                    attachment_count: task.attachment_count,
                })
            })
            .collect::<Result<Vec<_>, ApiError>>()?,
        statistics: PlanStatistics {
            task_count: statistics.task_count,
            completed_count: statistics.completed_count,
            overdue_count: statistics.overdue_count,
            cross_day_count: statistics.cross_day_count,
            total_estimate_minutes: statistics.total_estimate_minutes,
            by_status: BTreeMap::new(),
            by_priority: BTreeMap::new(),
            by_assignee: BTreeMap::new(),
        },
    })
}

/// Convert one R3 role into protobuf.
pub fn plan_actor_role_to_proto(value: PlanActorRole) -> v1::PlanActorRole {
    match value {
        PlanActorRole::Viewer => v1::PlanActorRole::Viewer,
        PlanActorRole::Editor => v1::PlanActorRole::Editor,
        PlanActorRole::Admin => v1::PlanActorRole::Admin,
    }
}

/// Decode one R3 role from protobuf.
pub fn plan_actor_role_from_proto(value: i32) -> Result<PlanActorRole, ApiError> {
    match v1::PlanActorRole::try_from(value) {
        Ok(v1::PlanActorRole::Viewer) => Ok(PlanActorRole::Viewer),
        Ok(v1::PlanActorRole::Editor) => Ok(PlanActorRole::Editor),
        Ok(v1::PlanActorRole::Admin) => Ok(PlanActorRole::Admin),
        _ => Err(ApiError::InvalidArgument(
            "actor_role must be viewer, editor, or admin".to_owned(),
        )),
    }
}

/// Map one R3 domain error into the shared API error shape.
pub fn plan_error_to_api(error: PlanError) -> ApiError {
    match error.code.as_str() {
        "revision_conflict" => ApiError::Conflict {
            current_revision: error.current_revision,
            entity_id: error
                .task_id
                .as_deref()
                .and_then(|value| value.parse().ok()),
            current_entity_version: error.current_task_version,
        },
        "version_conflict" => ApiError::Conflict {
            current_revision: error.current_revision,
            entity_id: error
                .task_id
                .as_deref()
                .and_then(|value| value.parse().ok()),
            current_entity_version: error.current_task_version,
        },
        "permission_denied" | "unknown_actor" => ApiError::PermissionDenied,
        "not_found" | "task_not_found" | "project_not_found" => ApiError::NotFound(error.message),
        "rollback_unavailable" | "dependency_cycle" | "child_tasks_exist" => {
            ApiError::FailedPrecondition(error.message)
        }
        code if code.starts_with("invalid_") || code == "attachment_policy" => {
            ApiError::InvalidArgument(error.message)
        }
        _ => ApiError::FailedPrecondition(error.message),
    }
}

fn parse_uuid(value: &str, field: &str) -> Result<Uuid, ApiError> {
    Uuid::parse_str(value).map_err(|_| ApiError::InvalidArgument(format!("{field} must be a UUID")))
}

fn parse_required_uuid_string(value: &str, field: &str) -> Result<String, ApiError> {
    parse_uuid(value, field).map(|value| value.to_string())
}

fn parse_date(value: &str, field: &str) -> Result<NaiveDate, ApiError> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ApiError::InvalidArgument(format!("{field} must use YYYY-MM-DD")))
}

fn task_status_to_proto(value: TaskStatus) -> v1::TaskStatus {
    match value {
        TaskStatus::Todo => v1::TaskStatus::Todo,
        TaskStatus::InProgress => v1::TaskStatus::InProgress,
        TaskStatus::Blocked => v1::TaskStatus::Blocked,
        TaskStatus::Done => v1::TaskStatus::Done,
    }
}

fn task_status_from_proto(value: i32) -> Result<TaskStatus, ApiError> {
    match v1::TaskStatus::try_from(value) {
        Ok(v1::TaskStatus::Todo) => Ok(TaskStatus::Todo),
        Ok(v1::TaskStatus::InProgress) => Ok(TaskStatus::InProgress),
        Ok(v1::TaskStatus::Blocked) => Ok(TaskStatus::Blocked),
        Ok(v1::TaskStatus::Done) => Ok(TaskStatus::Done),
        _ => Err(ApiError::InvalidArgument(
            "task status must be todo, in_progress, blocked, or done".to_owned(),
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

fn task_priority_from_proto(value: i32) -> Result<TaskPriority, ApiError> {
    match v1::TaskPriority::try_from(value) {
        Ok(v1::TaskPriority::None) => Ok(TaskPriority::Low),
        Ok(v1::TaskPriority::Low) => Ok(TaskPriority::Low),
        Ok(v1::TaskPriority::Medium) => Ok(TaskPriority::Medium),
        Ok(v1::TaskPriority::High) => Ok(TaskPriority::High),
        Ok(v1::TaskPriority::Urgent) => Ok(TaskPriority::Urgent),
        _ => Err(ApiError::InvalidArgument(
            "task priority must be none, low, medium, high, or urgent".to_owned(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plan_depth_snapshot_round_trips() {
        let snapshot = kshift_core::demo_snapshot(NaiveDate::from_ymd_opt(2026, 11, 14).unwrap());
        let decoded = plan_depth_snapshot_from_proto(plan_depth_snapshot_to_proto(&snapshot))
            .expect("snapshot should decode");
        assert_eq!(decoded, snapshot);
    }

    #[test]
    fn status_command_round_trips_without_client_actor_fields() {
        let input = PlanDepthCommandInput {
            request_id: Uuid::new_v4(),
            project_id: Uuid::new_v4(),
            expected_revision: 7,
            command: PlanCommand::SetTaskStatus {
                task_id: Uuid::new_v4().to_string(),
                status: TaskStatus::Done,
                expected_version: 3,
            },
        };
        let wire = plan_depth_command_to_proto(&input).expect("command should encode");
        let decoded = parse_execute_plan_depth_command(&wire).expect("command should decode");
        assert_eq!(decoded, input);
    }
}
