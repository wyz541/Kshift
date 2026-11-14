//! R3 plan-depth domain slice.
//!
//! The Rust core owns hierarchy, dependency, cross-day scheduling, attachment,
//! rollback and report invariants. SwiftUI receives immutable snapshots only.

use std::collections::{BTreeMap, HashMap, HashSet};

use chrono::{NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::model::{Person, TaskPriority, TaskStatus};

pub const PLAN_SCHEMA_VERSION: u32 = 1;
pub const MAX_DESCRIPTION_BYTES: usize = 256 * 1024;
pub const MAX_ATTACHMENT_BYTES: usize = 10 * 1024 * 1024;
pub const MAX_HISTORY_ENTRIES: usize = 100;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanProject {
    pub id: String,
    pub name: String,
    pub revision: u64,
    pub schema_version: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanTask {
    pub id: String,
    pub project_id: String,
    pub parent_id: Option<String>,
    pub title: String,
    pub description_markdown: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub assignee_id: Option<String>,
    pub starts_on: NaiveDate,
    pub due_on: NaiveDate,
    pub estimate_minutes: u32,
    pub position: i64,
    pub version: u64,
    pub completed_at: Option<String>,
}

impl PlanTask {
    pub fn is_cross_day(&self) -> bool {
        self.starts_on != self.due_on
    }

    pub fn is_overdue(&self, today: NaiveDate) -> bool {
        self.due_on < today && self.status != TaskStatus::Done
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct TaskDependency {
    pub task_id: String,
    pub depends_on_task_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AttachmentMetadata {
    pub id: String,
    pub sha256: String,
    pub media_type: String,
    pub byte_size: u64,
    pub filename: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct AttachmentLink {
    pub attachment_id: String,
    pub task_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanHistoryEntry {
    pub id: String,
    pub revision: u64,
    pub actor_id: String,
    pub action: String,
    pub summary: String,
    pub occurred_at: String,
    pub restored_from_revision: Option<u64>,
    pub content_sha256: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanDepthSnapshot {
    pub project: PlanProject,
    pub people: Vec<Person>,
    pub tasks: Vec<PlanTask>,
    pub dependencies: Vec<TaskDependency>,
    pub attachments: Vec<AttachmentMetadata>,
    pub attachment_links: Vec<AttachmentLink>,
    pub history: Vec<PlanHistoryEntry>,
}

impl PlanDepthSnapshot {
    pub fn content_sha256(&self) -> String {
        #[derive(Serialize)]
        struct Content<'a> {
            project_id: &'a str,
            tasks: &'a [PlanTask],
            dependencies: &'a [TaskDependency],
            attachments: &'a [AttachmentMetadata],
            attachment_links: &'a [AttachmentLink],
        }
        let content = Content {
            project_id: &self.project.id,
            tasks: &self.tasks,
            dependencies: &self.dependencies,
            attachments: &self.attachments,
            attachment_links: &self.attachment_links,
        };
        let encoded = serde_json::to_vec(&content).unwrap_or_default();
        hex_digest(&encoded)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanTaskDraft {
    pub parent_id: Option<String>,
    pub title: String,
    pub description_markdown: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub assignee_id: Option<String>,
    pub starts_on: NaiveDate,
    pub due_on: NaiveDate,
    pub estimate_minutes: u32,
    pub position: i64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum PlanActorRole {
    Viewer,
    Editor,
    Admin,
}

impl PlanActorRole {
    pub fn can_write(self) -> bool {
        self != Self::Viewer
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum PlanCommand {
    CreateTask {
        task_id: String,
        draft: PlanTaskDraft,
    },
    UpdateTask {
        task_id: String,
        expected_version: u64,
        draft: PlanTaskDraft,
    },
    DeleteTask {
        task_id: String,
        expected_version: u64,
    },
    SetParent {
        task_id: String,
        expected_version: u64,
        parent_id: Option<String>,
    },
    ReplaceDependencies {
        task_id: String,
        expected_version: u64,
        depends_on_task_ids: Vec<String>,
    },
    AttachFile {
        task_id: String,
        expected_version: u64,
        filename: String,
        declared_media_type: String,
        content: Vec<u8>,
    },
    Rollback {
        target_revision: u64,
        reason: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanCommandEnvelope {
    pub request_id: String,
    pub project_id: Uuid,
    pub expected_revision: u64,
    pub actor_id: String,
    pub actor_role: PlanActorRole,
    pub command: PlanCommand,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, thiserror::Error)]
#[error("{code}: {message}")]
pub struct PlanError {
    pub code: String,
    pub message: String,
    pub current_revision: Option<u64>,
    pub current_task_version: Option<u64>,
    pub task_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanCommandResponse {
    pub ok: bool,
    pub request_id: String,
    pub snapshot: PlanDepthSnapshot,
    pub affected_task_ids: Vec<String>,
    pub error: Option<PlanError>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ReportRange {
    pub starts_on: NaiveDate,
    pub ends_on: NaiveDate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ReportTask {
    pub id: String,
    pub title: String,
    pub parent_title: Option<String>,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub assignee_name: Option<String>,
    pub starts_on: NaiveDate,
    pub due_on: NaiveDate,
    pub estimate_minutes: u32,
    pub cross_day: bool,
    pub overdue: bool,
    pub dependency_count: u32,
    pub subtask_count: u32,
    pub attachment_count: u32,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanStatistics {
    pub task_count: u32,
    pub completed_count: u32,
    pub overdue_count: u32,
    pub cross_day_count: u32,
    pub total_estimate_minutes: u32,
    pub by_status: BTreeMap<String, u32>,
    pub by_priority: BTreeMap<String, u32>,
    pub by_assignee: BTreeMap<String, u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WorkReport {
    pub source_revision: u64,
    pub generated_at: String,
    pub range: ReportRange,
    pub tasks: Vec<ReportTask>,
    pub statistics: PlanStatistics,
}

#[derive(Debug, Clone)]
pub struct AttachmentPolicy;

#[derive(Debug, Clone)]
pub struct PreparedAttachment {
    pub sha256: String,
    pub media_type: String,
    pub filename: String,
    pub byte_size: u64,
}

impl AttachmentPolicy {
    pub fn prepare(
        filename: &str,
        declared_media_type: &str,
        content: &[u8],
    ) -> Result<PreparedAttachment, PlanError> {
        let filename = sanitize_filename(filename)?;
        if content.is_empty() {
            return Err(validation("附件不能为空。"));
        }
        if content.len() > MAX_ATTACHMENT_BYTES {
            return Err(validation("附件不能超过 10 MiB。"));
        }
        let media_type = detect_media_type(&filename, content)?;
        if declared_media_type != media_type {
            return Err(validation(format!(
                "附件声明类型与内容不一致，应为 {media_type}。"
            )));
        }
        Ok(PreparedAttachment {
            sha256: hex_digest(content),
            media_type: media_type.to_owned(),
            filename,
            byte_size: content.len() as u64,
        })
    }
}

#[derive(Debug, Clone)]
pub struct PlanDepthStore {
    snapshot: PlanDepthSnapshot,
    state_by_revision: HashMap<u64, PlanDepthSnapshot>,
    responses: HashMap<String, PlanCommandResponse>,
    attachment_bytes: HashMap<String, Vec<u8>>,
}

impl PlanDepthStore {
    pub fn new(snapshot: PlanDepthSnapshot) -> Result<Self, PlanError> {
        validate_snapshot(&snapshot)?;
        let mut state_by_revision = HashMap::new();
        state_by_revision.insert(snapshot.project.revision, snapshot.clone());
        Ok(Self {
            snapshot,
            state_by_revision,
            responses: HashMap::new(),
            attachment_bytes: HashMap::new(),
        })
    }

    pub fn with_history(
        snapshot: PlanDepthSnapshot,
        mut historical_states: Vec<PlanDepthSnapshot>,
    ) -> Result<Self, PlanError> {
        validate_snapshot(&snapshot)?;
        historical_states.push(snapshot.clone());
        let mut store = Self::new(snapshot)?;
        for state in historical_states {
            store
                .state_by_revision
                .insert(state.project.revision, state);
        }
        Ok(store)
    }

    pub fn snapshot(&self) -> &PlanDepthSnapshot {
        &self.snapshot
    }

    pub fn attachment_bytes(&self, sha256: &str) -> Option<&[u8]> {
        self.attachment_bytes.get(sha256).map(Vec::as_slice)
    }

    pub fn retained_attachment_sha256(&self) -> impl Iterator<Item = &str> {
        self.attachment_bytes.keys().map(String::as_str)
    }

    pub fn execute(&mut self, envelope: &PlanCommandEnvelope) -> PlanCommandResponse {
        if let Some(response) = self.responses.get(&envelope.request_id) {
            return response.clone();
        }
        if envelope.request_id.trim().is_empty() {
            return self.failure(
                envelope,
                "invalid_command",
                "请求 ID 不能为空。",
                None,
                None,
                None,
            );
        }
        if envelope.project_id.to_string() != self.snapshot.project.id {
            return self.failure(
                envelope,
                "invalid_project",
                "命令项目与快照项目不一致。",
                Some(self.snapshot.project.revision),
                None,
                None,
            );
        }
        if envelope.expected_revision != self.snapshot.project.revision {
            return self.failure(
                envelope,
                "revision_conflict",
                "项目已被其他成员更新。请刷新后重试。",
                Some(self.snapshot.project.revision),
                None,
                None,
            );
        }
        if !envelope.actor_role.can_write() {
            return self.failure(
                envelope,
                "permission_denied",
                "当前角色没有写入权限。",
                Some(self.snapshot.project.revision),
                None,
                None,
            );
        }
        if !self
            .snapshot
            .people
            .iter()
            .any(|person| person.id == envelope.actor_id)
        {
            return self.failure(
                envelope,
                "unknown_actor",
                "当前成员不在此项目中。",
                None,
                None,
                None,
            );
        }

        let mut next = self.snapshot.clone();
        let result = match &envelope.command {
            PlanCommand::CreateTask { task_id, draft } => {
                apply_create_task(&mut next, task_id, draft, envelope)
            }
            PlanCommand::UpdateTask {
                task_id,
                expected_version,
                draft,
            } => apply_update_task(&mut next, task_id, *expected_version, draft, envelope),
            PlanCommand::DeleteTask {
                task_id,
                expected_version,
            } => apply_delete_task(&mut next, task_id, *expected_version),
            PlanCommand::SetParent {
                task_id,
                expected_version,
                parent_id,
            } => apply_set_parent(&mut next, task_id, *expected_version, parent_id.as_deref()),
            PlanCommand::ReplaceDependencies {
                task_id,
                expected_version,
                depends_on_task_ids,
            } => apply_replace_dependencies(
                &mut next,
                task_id,
                *expected_version,
                depends_on_task_ids,
            ),
            PlanCommand::AttachFile {
                task_id,
                expected_version,
                filename,
                declared_media_type,
                content,
            } => apply_attachment(
                &mut next,
                &mut self.attachment_bytes,
                task_id,
                *expected_version,
                filename,
                declared_media_type,
                content,
            ),
            PlanCommand::Rollback {
                target_revision,
                reason,
            } => {
                if envelope.actor_role != PlanActorRole::Admin {
                    return self.failure(
                        envelope,
                        "permission_denied",
                        "只有 Admin 可以回退历史。",
                        Some(self.snapshot.project.revision),
                        None,
                        None,
                    );
                }
                apply_rollback(
                    &mut next,
                    &self.state_by_revision,
                    *target_revision,
                    reason,
                    envelope,
                )
            }
        };

        if let Err(mut error) = result {
            error.current_revision.get_or_insert(next.project.revision);
            return PlanCommandResponse {
                ok: false,
                request_id: envelope.request_id.clone(),
                snapshot: self.snapshot.clone(),
                affected_task_ids: affected_task_id(&envelope.command),
                error: Some(error),
            };
        }
        next.project.revision = self.snapshot.project.revision.saturating_add(1);
        let action = action_name(&envelope.command);
        let summary = command_summary(&envelope.command);
        next.history.insert(
            0,
            PlanHistoryEntry {
                id: format!("history-{}", next.project.revision),
                revision: next.project.revision,
                actor_id: envelope.actor_id.clone(),
                action: action.to_owned(),
                summary,
                occurred_at: Utc::now().to_rfc3339(),
                restored_from_revision: match envelope.command {
                    PlanCommand::Rollback {
                        target_revision, ..
                    } => Some(target_revision),
                    _ => None,
                },
                content_sha256: next.content_sha256(),
            },
        );
        next.history.truncate(MAX_HISTORY_ENTRIES);

        if let Err(error) = validate_snapshot(&next) {
            return PlanCommandResponse {
                ok: false,
                request_id: envelope.request_id.clone(),
                snapshot: self.snapshot.clone(),
                affected_task_ids: affected_task_id(&envelope.command),
                error: Some(error),
            };
        }

        self.snapshot = next;
        self.state_by_revision
            .insert(self.snapshot.project.revision, self.snapshot.clone());
        if self.state_by_revision.len() > MAX_HISTORY_ENTRIES {
            let oldest = self
                .state_by_revision
                .keys()
                .copied()
                .filter(|revision| *revision != self.snapshot.project.revision)
                .min();
            if let Some(oldest) = oldest {
                self.state_by_revision.remove(&oldest);
            }
        }
        let response = PlanCommandResponse {
            ok: true,
            request_id: envelope.request_id.clone(),
            snapshot: self.snapshot.clone(),
            affected_task_ids: affected_task_id(&envelope.command),
            error: None,
        };
        self.responses
            .insert(envelope.request_id.clone(), response.clone());
        response
    }

    pub fn report(&self, range: &ReportRange, today: NaiveDate) -> Result<WorkReport, PlanError> {
        if range.starts_on > range.ends_on {
            return Err(validation("报告日期范围无效。"));
        }
        let people: HashMap<_, _> = self
            .snapshot
            .people
            .iter()
            .map(|person| (person.id.as_str(), person.name.as_str()))
            .collect();
        let titles: HashMap<_, _> = self
            .snapshot
            .tasks
            .iter()
            .map(|task| (task.id.as_str(), task.title.as_str()))
            .collect();
        let dependency_counts = self.snapshot.dependencies.iter().fold(
            HashMap::<&str, u32>::new(),
            |mut counts, dependency| {
                *counts.entry(dependency.task_id.as_str()).or_default() += 1;
                counts
            },
        );
        let subtask_counts =
            self.snapshot
                .tasks
                .iter()
                .fold(HashMap::<&str, u32>::new(), |mut counts, task| {
                    if let Some(parent_id) = task.parent_id.as_deref() {
                        *counts.entry(parent_id).or_default() += 1;
                    }
                    counts
                });
        let attachment_counts = self.snapshot.attachment_links.iter().fold(
            HashMap::<&str, u32>::new(),
            |mut counts, link| {
                *counts.entry(link.task_id.as_str()).or_default() += 1;
                counts
            },
        );

        let mut report_tasks = Vec::new();
        for task in &self.snapshot.tasks {
            let scheduled = task.starts_on <= range.ends_on && task.due_on >= range.starts_on;
            let completed = task.completed_at.as_deref().is_some_and(|value| {
                value
                    .get(..10)
                    .and_then(|date| NaiveDate::parse_from_str(date, "%Y-%m-%d").ok())
                    .is_some_and(|date| date >= range.starts_on && date <= range.ends_on)
            });
            if !scheduled && !completed {
                continue;
            }
            report_tasks.push(ReportTask {
                id: task.id.clone(),
                title: task.title.clone(),
                parent_title: task
                    .parent_id
                    .as_deref()
                    .and_then(|id| titles.get(id))
                    .map(|title| (*title).to_owned()),
                status: task.status,
                priority: task.priority,
                assignee_name: task
                    .assignee_id
                    .as_deref()
                    .and_then(|id| people.get(id))
                    .map(|name| (*name).to_owned()),
                starts_on: task.starts_on,
                due_on: task.due_on,
                estimate_minutes: task.estimate_minutes,
                cross_day: task.is_cross_day(),
                overdue: task.is_overdue(today),
                dependency_count: dependency_counts
                    .get(task.id.as_str())
                    .copied()
                    .unwrap_or(0),
                subtask_count: subtask_counts.get(task.id.as_str()).copied().unwrap_or(0),
                attachment_count: attachment_counts
                    .get(task.id.as_str())
                    .copied()
                    .unwrap_or(0),
            });
        }
        report_tasks.sort_by_key(|task| (task.starts_on, task.due_on, task.title.clone()));

        let mut statistics = PlanStatistics {
            task_count: report_tasks.len() as u32,
            ..PlanStatistics::default()
        };
        for task in &report_tasks {
            statistics.total_estimate_minutes = statistics
                .total_estimate_minutes
                .saturating_add(task.estimate_minutes);
            *statistics
                .by_status
                .entry(status_key(task.status).to_owned())
                .or_default() += 1;
            *statistics
                .by_priority
                .entry(priority_key(task.priority).to_owned())
                .or_default() += 1;
            *statistics
                .by_assignee
                .entry(
                    task.assignee_name
                        .clone()
                        .unwrap_or_else(|| "未分配".to_owned()),
                )
                .or_default() += 1;
            statistics.completed_count += u32::from(task.status == TaskStatus::Done);
            statistics.overdue_count += u32::from(task.overdue);
            statistics.cross_day_count += u32::from(task.cross_day);
        }

        Ok(WorkReport {
            source_revision: self.snapshot.project.revision,
            generated_at: Utc::now().to_rfc3339(),
            range: range.clone(),
            tasks: report_tasks,
            statistics,
        })
    }

    fn failure(
        &self,
        envelope: &PlanCommandEnvelope,
        code: &str,
        message: &str,
        current_revision: Option<u64>,
        current_task_version: Option<u64>,
        task_id: Option<String>,
    ) -> PlanCommandResponse {
        PlanCommandResponse {
            ok: false,
            request_id: envelope.request_id.clone(),
            snapshot: self.snapshot.clone(),
            affected_task_ids: task_id.into_iter().collect(),
            error: Some(PlanError {
                code: code.to_owned(),
                message: message.to_owned(),
                current_revision,
                current_task_version,
                task_id: affected_task_id(&envelope.command).into_iter().next(),
            }),
        }
    }
}

fn apply_create_task(
    snapshot: &mut PlanDepthSnapshot,
    task_id: &str,
    draft: &PlanTaskDraft,
    envelope: &PlanCommandEnvelope,
) -> Result<(), PlanError> {
    if snapshot.tasks.iter().any(|task| task.id == task_id) {
        return Err(validation("任务 ID 已存在。"));
    }
    snapshot.tasks.push(task_from_draft(
        snapshot,
        task_id.to_owned(),
        1,
        draft,
        envelope,
    ));
    Ok(())
}

fn apply_update_task(
    snapshot: &mut PlanDepthSnapshot,
    task_id: &str,
    expected_version: u64,
    draft: &PlanTaskDraft,
    envelope: &PlanCommandEnvelope,
) -> Result<(), PlanError> {
    let index = task_index(snapshot, task_id)?;
    if snapshot.tasks[index].version != expected_version {
        return Err(version_conflict(snapshot.tasks[index].version, task_id));
    }
    let task = task_from_draft(
        snapshot,
        task_id.to_owned(),
        expected_version.saturating_add(1),
        draft,
        envelope,
    );
    snapshot.tasks[index] = task;
    Ok(())
}

fn apply_delete_task(
    snapshot: &mut PlanDepthSnapshot,
    task_id: &str,
    expected_version: u64,
) -> Result<(), PlanError> {
    let index = task_index(snapshot, task_id)?;
    if snapshot.tasks[index].version != expected_version {
        return Err(version_conflict(snapshot.tasks[index].version, task_id));
    }
    if snapshot
        .tasks
        .iter()
        .any(|task| task.parent_id.as_deref() == Some(task_id))
    {
        return Err(validation("请先删除或移动子任务。"));
    }
    snapshot.tasks.remove(index);
    snapshot.dependencies.retain(|dependency| {
        dependency.task_id != task_id && dependency.depends_on_task_id != task_id
    });
    snapshot
        .attachment_links
        .retain(|link| link.task_id != task_id);
    Ok(())
}

fn apply_set_parent(
    snapshot: &mut PlanDepthSnapshot,
    task_id: &str,
    expected_version: u64,
    parent_id: Option<&str>,
) -> Result<(), PlanError> {
    let index = task_index(snapshot, task_id)?;
    if snapshot.tasks[index].version != expected_version {
        return Err(version_conflict(snapshot.tasks[index].version, task_id));
    }
    snapshot.tasks[index].parent_id = parent_id.map(str::to_owned);
    snapshot.tasks[index].version = expected_version.saturating_add(1);
    Ok(())
}

fn apply_replace_dependencies(
    snapshot: &mut PlanDepthSnapshot,
    task_id: &str,
    expected_version: u64,
    depends_on_task_ids: &[String],
) -> Result<(), PlanError> {
    let index = task_index(snapshot, task_id)?;
    if snapshot.tasks[index].version != expected_version {
        return Err(version_conflict(snapshot.tasks[index].version, task_id));
    }
    snapshot
        .dependencies
        .retain(|dependency| dependency.task_id != task_id);
    for depends_on in depends_on_task_ids {
        snapshot.dependencies.push(TaskDependency {
            task_id: task_id.to_owned(),
            depends_on_task_id: depends_on.clone(),
        });
    }
    snapshot.tasks[index].version = expected_version.saturating_add(1);
    Ok(())
}

fn apply_attachment(
    snapshot: &mut PlanDepthSnapshot,
    attachment_bytes: &mut HashMap<String, Vec<u8>>,
    task_id: &str,
    expected_version: u64,
    filename: &str,
    declared_media_type: &str,
    content: &[u8],
) -> Result<(), PlanError> {
    let index = task_index(snapshot, task_id)?;
    if snapshot.tasks[index].version != expected_version {
        return Err(version_conflict(snapshot.tasks[index].version, task_id));
    }
    let prepared = AttachmentPolicy::prepare(filename, declared_media_type, content)?;
    let attachment = if let Some(existing) = snapshot
        .attachments
        .iter()
        .find(|attachment| attachment.sha256 == prepared.sha256)
    {
        existing.clone()
    } else {
        let attachment = AttachmentMetadata {
            id: format!("attachment-{}", &prepared.sha256[..12]),
            sha256: prepared.sha256.clone(),
            media_type: prepared.media_type,
            byte_size: prepared.byte_size,
            filename: prepared.filename,
        };
        snapshot.attachments.push(attachment.clone());
        attachment_bytes.insert(prepared.sha256, content.to_vec());
        attachment
    };
    let link = AttachmentLink {
        attachment_id: attachment.id,
        task_id: task_id.to_owned(),
    };
    if !snapshot.attachment_links.contains(&link) {
        snapshot.attachment_links.push(link);
    }
    snapshot.tasks[index].version = expected_version.saturating_add(1);
    Ok(())
}

fn apply_rollback(
    snapshot: &mut PlanDepthSnapshot,
    state_by_revision: &HashMap<u64, PlanDepthSnapshot>,
    target_revision: u64,
    reason: &str,
    envelope: &PlanCommandEnvelope,
) -> Result<(), PlanError> {
    if reason.trim().is_empty() {
        return Err(validation("回退原因不能为空。"));
    }
    if target_revision >= snapshot.project.revision {
        return Err(validation("回退目标必须早于当前版本。"));
    }
    let target = state_by_revision
        .get(&target_revision)
        .ok_or_else(|| PlanError {
            code: "rollback_unavailable".to_owned(),
            message: "目标版本已不在本机历史窗口内。".to_owned(),
            current_revision: Some(snapshot.project.revision),
            current_task_version: None,
            task_id: None,
        })?;
    let current_history = snapshot.history.clone();
    snapshot.tasks = target.tasks.clone();
    snapshot.dependencies = target.dependencies.clone();
    snapshot.attachments = target.attachments.clone();
    snapshot.attachment_links = target.attachment_links.clone();
    snapshot.history = current_history;
    if !snapshot
        .people
        .iter()
        .any(|person| person.id == envelope.actor_id)
    {
        return Err(validation("回退操作者不是项目成员。"));
    }
    Ok(())
}

fn task_from_draft(
    snapshot: &PlanDepthSnapshot,
    task_id: String,
    version: u64,
    draft: &PlanTaskDraft,
    _envelope: &PlanCommandEnvelope,
) -> PlanTask {
    let completed_at = if draft.status == TaskStatus::Done {
        Some(Utc::now().to_rfc3339())
    } else {
        None
    };
    PlanTask {
        id: task_id,
        project_id: snapshot.project.id.clone(),
        parent_id: draft.parent_id.clone(),
        title: draft.title.trim().to_owned(),
        description_markdown: draft.description_markdown.clone(),
        status: draft.status,
        priority: draft.priority,
        assignee_id: draft.assignee_id.clone(),
        starts_on: draft.starts_on,
        due_on: draft.due_on,
        estimate_minutes: draft.estimate_minutes,
        position: draft.position,
        version,
        completed_at,
    }
}

pub fn validate_snapshot(snapshot: &PlanDepthSnapshot) -> Result<(), PlanError> {
    let task_ids = unique_task_ids(snapshot)?;
    validate_tasks(snapshot, &task_ids)?;
    validate_parents(snapshot, &task_ids)?;
    validate_dependencies(snapshot, &task_ids)?;
    validate_attachments(snapshot, &task_ids)?;
    Ok(())
}

fn unique_task_ids(snapshot: &PlanDepthSnapshot) -> Result<HashSet<&str>, PlanError> {
    let mut ids = HashSet::new();
    for task in &snapshot.tasks {
        if task.project_id != snapshot.project.id {
            return Err(validation("任务不属于当前项目。"));
        }
        if !ids.insert(task.id.as_str()) {
            return Err(validation("任务 ID 重复。"));
        }
    }
    Ok(ids)
}

fn validate_tasks(snapshot: &PlanDepthSnapshot, ids: &HashSet<&str>) -> Result<(), PlanError> {
    let people: HashSet<_> = snapshot
        .people
        .iter()
        .map(|person| person.id.as_str())
        .collect();
    for task in &snapshot.tasks {
        if task.title.trim().is_empty() || task.title.chars().count() > 200 {
            return Err(validation("任务标题长度无效。"));
        }
        if task.description_markdown.len() > MAX_DESCRIPTION_BYTES {
            return Err(validation("Markdown 描述超过 256 KiB。"));
        }
        if task.starts_on > task.due_on {
            return Err(validation("任务开始日期不能晚于截止日期。"));
        }
        if task
            .assignee_id
            .as_deref()
            .is_some_and(|assignee| !people.contains(assignee))
        {
            return Err(validation("负责人不是项目成员。"));
        }
        if let Some(parent_id) = task.parent_id.as_deref()
            && !ids.contains(parent_id)
        {
            return Err(validation("父任务不存在或已跨项目。"));
        }
    }
    Ok(())
}

fn validate_parents(snapshot: &PlanDepthSnapshot, ids: &HashSet<&str>) -> Result<(), PlanError> {
    let parents: HashMap<_, _> = snapshot
        .tasks
        .iter()
        .map(|task| (task.id.as_str(), task.parent_id.as_deref()))
        .collect();
    for task in &snapshot.tasks {
        let mut visiting = HashSet::new();
        let mut cursor = Some(task.id.as_str());
        while let Some(id) = cursor {
            if !visiting.insert(id) {
                return Err(PlanError {
                    code: "subtask_cycle".to_owned(),
                    message: "子任务层级形成循环。".to_owned(),
                    current_revision: Some(snapshot.project.revision),
                    current_task_version: None,
                    task_id: Some(task.id.clone()),
                });
            }
            cursor = parents
                .get(id)
                .copied()
                .flatten()
                .filter(|parent| ids.contains(parent));
        }
    }
    Ok(())
}

fn validate_dependencies(
    snapshot: &PlanDepthSnapshot,
    ids: &HashSet<&str>,
) -> Result<(), PlanError> {
    let mut graph: HashMap<&str, Vec<&str>> = HashMap::new();
    let mut seen = HashSet::new();
    for dependency in &snapshot.dependencies {
        if !ids.contains(dependency.task_id.as_str())
            || !ids.contains(dependency.depends_on_task_id.as_str())
        {
            return Err(validation("依赖任务不存在或已跨项目。"));
        }
        if dependency.task_id == dependency.depends_on_task_id {
            return Err(dependency_cycle(Some(dependency.task_id.clone())));
        }
        if !seen.insert((
            dependency.task_id.as_str(),
            dependency.depends_on_task_id.as_str(),
        )) {
            return Err(validation("依赖关系重复。"));
        }
        graph
            .entry(dependency.task_id.as_str())
            .or_default()
            .push(dependency.depends_on_task_id.as_str());
    }
    let mut visited = HashSet::new();
    let mut visiting = HashSet::new();
    for id in ids {
        if dependency_has_cycle(id, &graph, &mut visiting, &mut visited) {
            return Err(dependency_cycle(Some((*id).to_owned())));
        }
    }
    Ok(())
}

fn dependency_has_cycle<'a>(
    node: &'a str,
    graph: &HashMap<&'a str, Vec<&'a str>>,
    visiting: &mut HashSet<&'a str>,
    visited: &mut HashSet<&'a str>,
) -> bool {
    if visited.contains(node) {
        return false;
    }
    if !visiting.insert(node) {
        return true;
    }
    if let Some(next_nodes) = graph.get(node) {
        for next in next_nodes {
            if dependency_has_cycle(next, graph, visiting, visited) {
                return true;
            }
        }
    }
    visiting.remove(node);
    visited.insert(node);
    false
}

fn validate_attachments(
    snapshot: &PlanDepthSnapshot,
    task_ids: &HashSet<&str>,
) -> Result<(), PlanError> {
    let mut attachment_ids = HashSet::new();
    let mut hashes = HashSet::new();
    for attachment in &snapshot.attachments {
        if !attachment_ids.insert(attachment.id.as_str()) {
            return Err(validation("附件 ID 重复。"));
        }
        if !hashes.insert(attachment.sha256.as_str()) {
            return Err(validation("附件内容未按 SHA-256 去重。"));
        }
        if attachment.sha256.len() != 64 {
            return Err(validation("附件 SHA-256 长度无效。"));
        }
        if attachment.byte_size > MAX_ATTACHMENT_BYTES as u64 {
            return Err(validation("附件不能超过 10 MiB。"));
        }
    }
    let mut links = HashSet::new();
    for link in &snapshot.attachment_links {
        if !attachment_ids.contains(link.attachment_id.as_str()) {
            return Err(validation("附件不存在。"));
        }
        if !task_ids.contains(link.task_id.as_str()) {
            return Err(validation("附件任务不存在。"));
        }
        if !links.insert((link.attachment_id.as_str(), link.task_id.as_str())) {
            return Err(validation("附件链接重复。"));
        }
    }
    Ok(())
}

fn task_index(snapshot: &PlanDepthSnapshot, task_id: &str) -> Result<usize, PlanError> {
    snapshot
        .tasks
        .iter()
        .position(|task| task.id == task_id)
        .ok_or_else(|| PlanError {
            code: "task_not_found".to_owned(),
            message: "任务不存在。".to_owned(),
            current_revision: Some(snapshot.project.revision),
            current_task_version: None,
            task_id: Some(task_id.to_owned()),
        })
}

fn version_conflict(current: u64, task_id: &str) -> PlanError {
    PlanError {
        code: "version_conflict".to_owned(),
        message: "任务已被其他成员更新。请刷新后重试。".to_owned(),
        current_revision: None,
        current_task_version: Some(current),
        task_id: Some(task_id.to_owned()),
    }
}

fn dependency_cycle(task_id: Option<String>) -> PlanError {
    PlanError {
        code: "dependency_cycle".to_owned(),
        message: "任务依赖不能形成循环。".to_owned(),
        current_revision: None,
        current_task_version: None,
        task_id,
    }
}

fn validation(message: impl Into<String>) -> PlanError {
    PlanError {
        code: "validation_error".to_owned(),
        message: message.into(),
        current_revision: None,
        current_task_version: None,
        task_id: None,
    }
}

fn affected_task_id(command: &PlanCommand) -> Vec<String> {
    match command {
        PlanCommand::CreateTask { task_id, .. }
        | PlanCommand::UpdateTask { task_id, .. }
        | PlanCommand::DeleteTask { task_id, .. }
        | PlanCommand::SetParent { task_id, .. }
        | PlanCommand::ReplaceDependencies { task_id, .. }
        | PlanCommand::AttachFile { task_id, .. } => vec![task_id.clone()],
        PlanCommand::Rollback { .. } => Vec::new(),
    }
}

fn action_name(command: &PlanCommand) -> &'static str {
    match command {
        PlanCommand::CreateTask { .. } => "created",
        PlanCommand::UpdateTask { .. } => "updated",
        PlanCommand::DeleteTask { .. } => "deleted",
        PlanCommand::SetParent { .. } => "parent_changed",
        PlanCommand::ReplaceDependencies { .. } => "dependencies_replaced",
        PlanCommand::AttachFile { .. } => "attachment_added",
        PlanCommand::Rollback { .. } => "rollback",
    }
}

fn command_summary(command: &PlanCommand) -> String {
    match command {
        PlanCommand::CreateTask { draft, .. } => format!("创建任务「{}」", draft.title),
        PlanCommand::UpdateTask { draft, .. } => format!("更新任务「{}」", draft.title),
        PlanCommand::DeleteTask { task_id, .. } => format!("删除任务 {task_id}"),
        PlanCommand::SetParent { task_id, .. } => format!("调整任务 {task_id} 的父任务"),
        PlanCommand::ReplaceDependencies { task_id, .. } => {
            format!("替换任务 {task_id} 的依赖")
        }
        PlanCommand::AttachFile { filename, .. } => format!("添加附件「{filename}」"),
        PlanCommand::Rollback {
            target_revision,
            reason,
        } => {
            format!("回退到版本 {target_revision}：{reason}")
        }
    }
}

fn status_key(status: TaskStatus) -> &'static str {
    match status {
        TaskStatus::Todo => "todo",
        TaskStatus::InProgress => "in_progress",
        TaskStatus::Blocked => "blocked",
        TaskStatus::Done => "done",
    }
}

fn priority_key(priority: TaskPriority) -> &'static str {
    match priority {
        TaskPriority::Low => "low",
        TaskPriority::Medium => "medium",
        TaskPriority::High => "high",
        TaskPriority::Urgent => "urgent",
    }
}

fn sanitize_filename(filename: &str) -> Result<String, PlanError> {
    let basename = filename
        .replace('\\', "/")
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .trim()
        .to_owned();
    if basename.is_empty() || basename == "." || basename == ".." || basename.len() > 200 {
        return Err(validation("附件文件名无效。"));
    }
    Ok(basename)
}

fn detect_media_type(filename: &str, content: &[u8]) -> Result<&'static str, PlanError> {
    let extension = filename
        .rsplit_once('.')
        .map(|(_, extension)| extension.to_ascii_lowercase())
        .ok_or_else(|| validation("附件需要文件扩展名。"))?;
    let media_type = match extension.as_str() {
        "md" if std::str::from_utf8(content).is_ok() => "text/markdown",
        "txt" if std::str::from_utf8(content).is_ok() => "text/plain",
        "csv" if std::str::from_utf8(content).is_ok() => "text/csv",
        "json" if serde_json::from_slice::<serde_json::Value>(content).is_ok() => {
            "application/json"
        }
        "png" if content.starts_with(b"\x89PNG\r\n\x1a\n") => "image/png",
        "jpg" | "jpeg" if content.starts_with(&[0xff, 0xd8, 0xff]) => "image/jpeg",
        "gif" if content.starts_with(b"GIF87a") || content.starts_with(b"GIF89a") => "image/gif",
        "webp" if content.len() >= 12 && &content[..4] == b"RIFF" && &content[8..12] == b"WEBP" => {
            "image/webp"
        }
        "pdf" if content.starts_with(b"%PDF-") => "application/pdf",
        _ => return Err(validation("附件类型不允许，或内容与扩展名不匹配。")),
    };
    Ok(media_type)
}

fn hex_digest(content: &[u8]) -> String {
    Sha256::digest(content)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

pub fn build_report_html(report: &WorkReport) -> String {
    let mut rows = String::new();
    for task in &report.tasks {
        rows.push_str(&format!(
            "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>",
            html_escape(&task.title),
            status_key(task.status),
            priority_key(task.priority),
            html_escape(task.assignee_name.as_deref().unwrap_or("未分配")),
            task.starts_on,
            task.due_on,
            task.estimate_minutes,
            task.attachment_count,
        ));
    }
    format!(
        "<!doctype html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\"><title>Kshift 工作报告</title><style>body{{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:960px;margin:40px auto;color:#111}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #ddd;padding:8px;text-align:left}}th{{background:#f4f4f4}}.meta{{color:#666}}</style></head><body><h1>工作报告</h1><p class=\"meta\">来源版本 revision {}</p><p class=\"meta\">日期 {} 至 {} · 生成于 {}</p><section><h2>统计</h2><p>任务 {} 项，完成 {} 项，逾期 {} 项，跨日 {} 项，预计 {} 分钟。</p></section><table><thead><tr><th>任务</th><th>状态</th><th>优先级</th><th>负责人</th><th>开始</th><th>截止</th><th>分钟</th><th>附件</th></tr></thead><tbody>{}</tbody></table></body></html>",
        report.source_revision,
        report.range.starts_on,
        report.range.ends_on,
        html_escape(&report.generated_at),
        report.statistics.task_count,
        report.statistics.completed_count,
        report.statistics.overdue_count,
        report.statistics.cross_day_count,
        report.statistics.total_estimate_minutes,
        rows,
    )
}

fn html_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

pub fn demo_snapshot(today: NaiveDate) -> PlanDepthSnapshot {
    let project = PlanProject {
        id: "d0000000-0000-4000-8000-000000000001".to_owned(),
        name: "Kshift 计划深度".to_owned(),
        revision: 7,
        schema_version: PLAN_SCHEMA_VERSION,
    };
    let people = vec![
        Person {
            id: "d0000000-0000-4000-8000-000000000002".to_owned(),
            name: "林澈".to_owned(),
            initials: "LC".to_owned(),
            color_hex: "#2F7CF6".to_owned(),
        },
        Person {
            id: "d0000000-0000-4000-8000-000000000003".to_owned(),
            name: "周宁".to_owned(),
            initials: "ZN".to_owned(),
            color_hex: "#2F9E6B".to_owned(),
        },
        Person {
            id: "d0000000-0000-4000-8000-000000000004".to_owned(),
            name: "陈默".to_owned(),
            initials: "CM".to_owned(),
            color_hex: "#D26A3B".to_owned(),
        },
    ];
    let task = |id: &str,
                parent: Option<&str>,
                title: &str,
                status: TaskStatus,
                priority: TaskPriority,
                assignee: &str,
                start_offset: i64,
                length: i64,
                estimate: u32,
                position: i64| PlanTask {
        id: id.to_owned(),
        project_id: project.id.clone(),
        parent_id: parent.map(str::to_owned),
        title: title.to_owned(),
        description_markdown: format!(
            "### 目标\n\n- 完成 **{title}**\n- 保留共享验收语义\n\n> 内容由 Rust snapshot 提供。"
        ),
        status,
        priority,
        assignee_id: Some(assignee.to_owned()),
        starts_on: today + chrono::Duration::days(start_offset),
        due_on: today + chrono::Duration::days(start_offset + length),
        estimate_minutes: estimate,
        position,
        version: 1,
        completed_at: (status == TaskStatus::Done).then(|| Utc::now().to_rfc3339()),
    };
    let tasks = vec![
        task(
            "task-plan",
            None,
            "冻结 R3 计划深度",
            TaskStatus::InProgress,
            TaskPriority::High,
            "d0000000-0000-4000-8000-000000000002",
            0,
            2,
            240,
            0,
        ),
        task(
            "task-deps",
            Some("task-plan"),
            "补齐依赖环检测",
            TaskStatus::Todo,
            TaskPriority::Urgent,
            "d0000000-0000-4000-8000-000000000003",
            1,
            1,
            90,
            1,
        ),
        task(
            "task-gantt",
            Some("task-plan"),
            "实现跨日甘特行",
            TaskStatus::Todo,
            TaskPriority::High,
            "d0000000-0000-4000-8000-000000000004",
            2,
            3,
            180,
            2,
        ),
        task(
            "task-report",
            None,
            "统一报告 source snapshot",
            TaskStatus::Blocked,
            TaskPriority::Urgent,
            "d0000000-0000-4000-8000-000000000002",
            1,
            2,
            150,
            3,
        ),
        task(
            "task-history",
            None,
            "验证回退审计",
            TaskStatus::Done,
            TaskPriority::Medium,
            "d0000000-0000-4000-8000-000000000003",
            -2,
            1,
            60,
            4,
        ),
    ];
    let dependencies = vec![
        TaskDependency {
            task_id: "task-deps".to_owned(),
            depends_on_task_id: "task-plan".to_owned(),
        },
        TaskDependency {
            task_id: "task-gantt".to_owned(),
            depends_on_task_id: "task-plan".to_owned(),
        },
        TaskDependency {
            task_id: "task-report".to_owned(),
            depends_on_task_id: "task-gantt".to_owned(),
        },
    ];
    let attachments = vec![AttachmentMetadata {
        id: "attachment-r3-spec".to_owned(),
        sha256: hex_digest(b"# R3 acceptance\n- cycles\n- reports\n"),
        media_type: "text/markdown".to_owned(),
        byte_size: 34,
        filename: "r3-acceptance.md".to_owned(),
    }];
    let attachment_links = vec![AttachmentLink {
        attachment_id: "attachment-r3-spec".to_owned(),
        task_id: "task-plan".to_owned(),
    }];
    let mut snapshot = PlanDepthSnapshot {
        project,
        people,
        tasks,
        dependencies,
        attachments,
        attachment_links,
        history: Vec::new(),
    };
    snapshot.history.push(PlanHistoryEntry {
        id: "history-7".to_owned(),
        revision: 7,
        actor_id: "d0000000-0000-4000-8000-000000000002".to_owned(),
        action: "seeded".to_owned(),
        summary: "载入 R3 计划深度示例".to_owned(),
        occurred_at: Utc::now().to_rfc3339(),
        restored_from_revision: None,
        content_sha256: snapshot.content_sha256(),
    });
    snapshot
}

#[cfg(test)]
mod tests {
    use super::*;

    fn today() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 11, 13).unwrap()
    }

    fn store() -> PlanDepthStore {
        PlanDepthStore::new(demo_snapshot(today())).unwrap()
    }

    fn envelope(
        request_id: &str,
        role: PlanActorRole,
        command: PlanCommand,
    ) -> PlanCommandEnvelope {
        PlanCommandEnvelope {
            request_id: request_id.to_owned(),
            project_id: Uuid::parse_str("d0000000-0000-4000-8000-000000000001").unwrap(),
            expected_revision: 7,
            actor_id: "d0000000-0000-4000-8000-000000000002".to_owned(),
            actor_role: role,
            command,
        }
    }

    #[test]
    fn rejects_direct_and_indirect_dependency_cycles() {
        let mut store = store();
        let command = envelope(
            "cycle",
            PlanActorRole::Editor,
            PlanCommand::ReplaceDependencies {
                task_id: "task-plan".to_owned(),
                expected_version: 1,
                depends_on_task_ids: vec!["task-report".to_owned()],
            },
        );
        let response = store.execute(&command);
        assert!(!response.ok);
        assert_eq!(response.error.unwrap().code, "dependency_cycle");
        assert_eq!(store.snapshot().project.revision, 7);
    }

    #[test]
    fn rejects_subtask_cycles_and_cross_day_errors() {
        let mut store = store();
        let response = store.execute(&envelope(
            "parent-cycle",
            PlanActorRole::Editor,
            PlanCommand::SetParent {
                task_id: "task-plan".to_owned(),
                expected_version: 1,
                parent_id: Some("task-gantt".to_owned()),
            },
        ));
        assert_eq!(response.error.unwrap().code, "subtask_cycle");

        let response = store.execute(&envelope(
            "bad-range",
            PlanActorRole::Editor,
            PlanCommand::CreateTask {
                task_id: "bad".to_owned(),
                draft: PlanTaskDraft {
                    parent_id: None,
                    title: "日期倒置".to_owned(),
                    description_markdown: String::new(),
                    status: TaskStatus::Todo,
                    priority: TaskPriority::Low,
                    assignee_id: None,
                    starts_on: today() + chrono::Duration::days(2),
                    due_on: today(),
                    estimate_minutes: 10,
                    position: 5,
                },
            },
        ));
        assert_eq!(response.error.unwrap().code, "validation_error");
    }

    #[test]
    fn attachment_is_type_checked_and_deduplicated_by_sha256() {
        let mut store = store();
        let content = b"same markdown".to_vec();
        let first = store.execute(&envelope(
            "attach-1",
            PlanActorRole::Editor,
            PlanCommand::AttachFile {
                task_id: "task-deps".to_owned(),
                expected_version: 1,
                filename: "one.md".to_owned(),
                declared_media_type: "text/markdown".to_owned(),
                content: content.clone(),
            },
        ));
        assert!(first.ok);
        let second = store.execute(&PlanCommandEnvelope {
            request_id: "attach-2".to_owned(),
            project_id: Uuid::parse_str("d0000000-0000-4000-8000-000000000001").unwrap(),
            expected_revision: first.snapshot.project.revision,
            actor_id: "d0000000-0000-4000-8000-000000000002".to_owned(),
            actor_role: PlanActorRole::Editor,
            command: PlanCommand::AttachFile {
                task_id: "task-gantt".to_owned(),
                expected_version: 1,
                filename: "two.md".to_owned(),
                declared_media_type: "text/markdown".to_owned(),
                content,
            },
        });
        assert!(second.ok);
        let digest = hex_digest(b"same markdown");
        assert_eq!(
            second
                .snapshot
                .attachments
                .iter()
                .filter(|attachment| attachment.sha256 == digest)
                .count(),
            1
        );
        assert_eq!(
            second
                .snapshot
                .attachment_links
                .iter()
                .filter(|link| {
                    second.snapshot.attachments.iter().any(|attachment| {
                        attachment.id == link.attachment_id && attachment.sha256 == digest
                    })
                })
                .count(),
            2
        );

        let bad = store.execute(&PlanCommandEnvelope {
            request_id: "attach-bad".to_owned(),
            project_id: Uuid::parse_str("d0000000-0000-4000-8000-000000000001").unwrap(),
            expected_revision: second.snapshot.project.revision,
            actor_id: "d0000000-0000-4000-8000-000000000002".to_owned(),
            actor_role: PlanActorRole::Editor,
            command: PlanCommand::AttachFile {
                task_id: "task-deps".to_owned(),
                expected_version: 2,
                filename: "evil.exe".to_owned(),
                declared_media_type: "application/octet-stream".to_owned(),
                content: b"MZ".to_vec(),
            },
        });
        assert_eq!(bad.error.unwrap().code, "validation_error");
    }

    #[test]
    fn rollback_requires_admin_and_records_restore_evidence() {
        let mut store = store();
        let created = store.execute(&envelope(
            "create",
            PlanActorRole::Editor,
            PlanCommand::CreateTask {
                task_id: "task-new".to_owned(),
                draft: PlanTaskDraft {
                    parent_id: None,
                    title: "临时任务".to_owned(),
                    description_markdown: String::new(),
                    status: TaskStatus::Todo,
                    priority: TaskPriority::Low,
                    assignee_id: Some("d0000000-0000-4000-8000-000000000002".to_owned()),
                    starts_on: today(),
                    due_on: today(),
                    estimate_minutes: 30,
                    position: 9,
                },
            },
        ));
        assert!(created.ok);
        let target_digest = store.state_by_revision[&7].content_sha256();

        let denied = store.execute(&PlanCommandEnvelope {
            request_id: "rollback-denied".to_owned(),
            project_id: Uuid::parse_str("d0000000-0000-4000-8000-000000000001").unwrap(),
            expected_revision: created.snapshot.project.revision,
            actor_id: "d0000000-0000-4000-8000-000000000002".to_owned(),
            actor_role: PlanActorRole::Editor,
            command: PlanCommand::Rollback {
                target_revision: 7,
                reason: "撤销示例任务".to_owned(),
            },
        });
        assert_eq!(denied.error.unwrap().code, "permission_denied");

        let rolled_back = store.execute(&PlanCommandEnvelope {
            request_id: "rollback-admin".to_owned(),
            project_id: Uuid::parse_str("d0000000-0000-4000-8000-000000000001").unwrap(),
            expected_revision: created.snapshot.project.revision,
            actor_id: "d0000000-0000-4000-8000-000000000002".to_owned(),
            actor_role: PlanActorRole::Admin,
            command: PlanCommand::Rollback {
                target_revision: 7,
                reason: "撤销示例任务".to_owned(),
            },
        });
        assert!(rolled_back.ok);
        assert_eq!(rolled_back.snapshot.project.revision, 9);
        let audit = &rolled_back.snapshot.history[0];
        assert_eq!(audit.action, "rollback");
        assert_eq!(audit.restored_from_revision, Some(7));
        assert_eq!(audit.content_sha256, target_digest);
        assert!(
            rolled_back
                .snapshot
                .tasks
                .iter()
                .all(|task| task.id != "task-new")
        );
    }

    #[test]
    fn work_report_and_html_share_one_source_revision() {
        let store = store();
        let report = store
            .report(
                &ReportRange {
                    starts_on: today() - chrono::Duration::days(3),
                    ends_on: today() + chrono::Duration::days(5),
                },
                today(),
            )
            .unwrap();
        assert_eq!(report.source_revision, store.snapshot().project.revision);
        assert!(report.statistics.cross_day_count > 0);
        assert!(report.statistics.completed_count > 0);
        let html = build_report_html(&report);
        assert!(html.contains(&format!("revision {}", report.source_revision)));
    }

    #[test]
    fn command_replay_does_not_increment_revision_twice() {
        let mut store = store();
        let command = envelope(
            "idempotent",
            PlanActorRole::Editor,
            PlanCommand::SetParent {
                task_id: "task-deps".to_owned(),
                expected_version: 1,
                parent_id: Some("task-plan".to_owned()),
            },
        );
        let first = store.execute(&command);
        let second = store.execute(&command);
        assert_eq!(first, second);
        assert_eq!(store.snapshot().project.revision, 8);
    }
}
