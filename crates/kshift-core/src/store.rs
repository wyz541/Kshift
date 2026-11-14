use std::collections::{HashMap, HashSet};

use chrono::{Duration, Local, SecondsFormat, Utc};
use thiserror::Error;

use crate::model::{
    CommandEnvelope, CommandError, CommandResponse, Person, ProjectAuditEntry, ProjectSnapshot,
    ProjectSummary, TaskCommand, TaskHistoryEntry, TaskItem, TaskPriority, TaskStatus,
};

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("project not found: {0}")]
    ProjectNotFound(String),
}

#[derive(Debug)]
struct ProjectState {
    summary: ProjectSummary,
    tasks: Vec<TaskItem>,
    audit: Vec<ProjectAuditEntry>,
}

#[derive(Debug)]
pub struct KshiftStore {
    projects: Vec<ProjectState>,
    people: Vec<Person>,
    processed: HashMap<(String, String), CommandResponse>,
    next_id: u64,
}

impl Default for KshiftStore {
    fn default() -> Self {
        Self::new()
    }
}

impl KshiftStore {
    pub fn new() -> Self {
        let today = Local::now().date_naive();
        let timestamp = now_timestamp();
        let people = vec![
            Person {
                id: "person-mia".into(),
                name: "Mia Chen".into(),
                initials: "MC".into(),
                color_hex: "#0A84FF".into(),
            },
            Person {
                id: "person-noah".into(),
                name: "Noah Li".into(),
                initials: "NL".into(),
                color_hex: "#30D158".into(),
            },
            Person {
                id: "person-ava".into(),
                name: "Ava Wang".into(),
                initials: "AW".into(),
                color_hex: "#FF9F0A".into(),
            },
            Person {
                id: "person-li".into(),
                name: "Li Zhou".into(),
                initials: "LZ".into(),
                color_hex: "#BF5AF2".into(),
            },
        ];
        let member_ids: Vec<String> = people.iter().map(|person| person.id.clone()).collect();

        let focus_summary = ProjectSummary {
            id: "project-focus-2026".into(),
            name: "Launch Room".into(),
            code: "FOCUS".into(),
            color_hex: "#0A84FF".into(),
            member_ids: member_ids.clone(),
            revision: 8,
        };
        let delta_summary = ProjectSummary {
            id: "project-customer".into(),
            name: "Customer Follow-up".into(),
            code: "CUSTOMER".into(),
            color_hex: "#FF9F0A".into(),
            member_ids,
            revision: 5,
        };

        let mut store = Self {
            projects: vec![
                ProjectState {
                    summary: focus_summary,
                    tasks: Vec::new(),
                    audit: Vec::new(),
                },
                ProjectState {
                    summary: delta_summary,
                    tasks: Vec::new(),
                    audit: Vec::new(),
                },
            ],
            people,
            processed: HashMap::new(),
            next_id: 100,
        };

        store.seed_task(
            0,
            "task-launch-brief",
            "确认发布简报",
            "汇总平台版本、风险和负责人。",
            TaskStatus::InProgress,
            TaskPriority::High,
            Some("person-mia"),
            today,
            1024,
            &timestamp,
        );
        store.seed_task(
            0,
            "task-ui-review",
            "Liquid Glass 视觉复核",
            "检查卡片对比度、Reduce Transparency 和 Increase Contrast。",
            TaskStatus::Todo,
            TaskPriority::Urgent,
            Some("person-noah"),
            today,
            2048,
            &timestamp,
        );
        store.seed_task(
            0,
            "task-accessibility",
            "完成 VoiceOver 清单",
            "覆盖看板卡片、编辑 Sheet 和冲突提示。",
            TaskStatus::Blocked,
            TaskPriority::High,
            Some("person-ava"),
            today,
            3072,
            &timestamp,
        );
        store.seed_task(
            0,
            "task-api-contract",
            "冻结客户端命令契约",
            "确认 revision 和 task version 的冲突语义。",
            TaskStatus::Done,
            TaskPriority::Medium,
            Some("person-li"),
            today,
            4096,
            &timestamp,
        );
        store.seed_task(
            0,
            "task-tomorrow-perf",
            "记录 iOS 滚动读数",
            "使用 Instruments 记录列表滚动和 Sheet 切换。",
            TaskStatus::Todo,
            TaskPriority::Medium,
            Some("person-noah"),
            today + Duration::days(1),
            1024,
            &timestamp,
        );
        store.seed_task(
            0,
            "task-yesterday-prototype",
            "确认原生 Glass API",
            "只使用 Apple 原生 GlassEffectContainer 和 glassEffect。",
            TaskStatus::Done,
            TaskPriority::Low,
            Some("person-mia"),
            today - Duration::days(1),
            1024,
            &timestamp,
        );
        store.seed_task(
            1,
            "task-customer-call",
            "回访试点团队",
            "确认下周试用人员。",
            TaskStatus::Todo,
            TaskPriority::High,
            Some("person-ava"),
            today,
            1024,
            &timestamp,
        );
        store.seed_task(
            1,
            "task-customer-notes",
            "整理客户需求",
            "把反馈按阻断和非阻断分组。",
            TaskStatus::InProgress,
            TaskPriority::Medium,
            Some("person-li"),
            today,
            2048,
            &timestamp,
        );

        store
    }

    pub fn project_summaries(&self) -> Vec<ProjectSummary> {
        self.projects
            .iter()
            .map(|project| project.summary.clone())
            .collect()
    }

    pub fn snapshot(&self, project_id: &str) -> Result<ProjectSnapshot, StoreError> {
        let project = self
            .projects
            .iter()
            .find(|project| project.summary.id == project_id)
            .ok_or_else(|| StoreError::ProjectNotFound(project_id.to_string()))?;
        Ok(self.snapshot_for(project))
    }

    pub fn execute(&mut self, project_id: &str, envelope: &CommandEnvelope) -> CommandResponse {
        let cache_key = (project_id.to_string(), envelope.request_id.clone());
        if let Some(response) = self.processed.get(&cache_key) {
            return response.clone();
        }

        let Some(project_index) = self
            .projects
            .iter()
            .position(|project| project.summary.id == project_id)
        else {
            return self.failure(
                project_id,
                &envelope.request_id,
                "project_not_found",
                "项目不存在。",
                None,
                None,
                None,
            );
        };

        if !self
            .people
            .iter()
            .any(|person| person.id == envelope.actor_id)
        {
            return self.failure(
                project_id,
                &envelope.request_id,
                "actor_not_found",
                "当前编辑者不存在。",
                None,
                None,
                None,
            );
        }

        let current_revision = self.projects[project_index].summary.revision;
        if envelope.expected_revision != current_revision {
            return self.failure(
                project_id,
                &envelope.request_id,
                "revision_conflict",
                "项目内容已变化。请刷新快照后再提交。",
                Some(current_revision),
                None,
                None,
            );
        }

        match &envelope.command {
            TaskCommand::CreateTask(command) => {
                if let Err(message) = self.validate_fields(
                    &command.title,
                    &command.notes,
                    command.assignee_id.as_deref(),
                ) {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "invalid_command",
                        message,
                        None,
                        None,
                        None,
                    );
                }

                let task_id = self.allocate_id("task");
                let history_id = self.allocate_id("history");
                let audit_id = self.allocate_id("audit");
                let timestamp = now_timestamp();
                let project = &mut self.projects[project_index];
                let position = command.position.unwrap_or_else(|| {
                    project
                        .tasks
                        .iter()
                        .filter(|task| {
                            task.assignee_id == command.assignee_id
                                && task.due_date == command.due_date
                        })
                        .map(|task| task.position)
                        .max()
                        .unwrap_or(0)
                        + 1024
                });
                let history = TaskHistoryEntry {
                    id: history_id,
                    revision: project.summary.revision + 1,
                    action: "created".into(),
                    summary: "创建任务".into(),
                    actor_id: envelope.actor_id.clone(),
                    occurred_at: timestamp.clone(),
                };
                project.tasks.push(TaskItem {
                    id: task_id.clone(),
                    project_id: project.summary.id.clone(),
                    title: command.title.trim().to_string(),
                    notes: command.notes.trim().to_string(),
                    status: command.status,
                    priority: command.priority,
                    assignee_id: command.assignee_id.clone(),
                    due_date: command.due_date,
                    position,
                    version: 1,
                    updated_at: timestamp.clone(),
                    updated_by: envelope.actor_id.clone(),
                    history: vec![history],
                });
                project.summary.revision += 1;
                project.audit.push(ProjectAuditEntry {
                    id: audit_id,
                    revision: project.summary.revision,
                    action: "created".into(),
                    summary: format!("创建任务「{}」", command.title.trim()),
                    task_id: Some(task_id.clone()),
                    actor_id: envelope.actor_id.clone(),
                    occurred_at: timestamp,
                });
                trim_audit(project);
                self.success(project_index, &envelope.request_id, vec![task_id])
            }
            TaskCommand::UpdateTask(command) => {
                if let Err(message) = self.validate_fields(
                    &command.title,
                    &command.notes,
                    command.assignee_id.as_deref(),
                ) {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "invalid_command",
                        message,
                        None,
                        None,
                        None,
                    );
                }

                let project = &self.projects[project_index];
                let Some(task_index) = project
                    .tasks
                    .iter()
                    .position(|task| task.id == command.task_id)
                else {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "task_not_found",
                        "任务不存在。",
                        Some(project.summary.revision),
                        None,
                        Some(command.task_id.clone()),
                    );
                };
                let current = &project.tasks[task_index];
                if current.version != command.expected_task_version {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "version_conflict",
                        "任务已被其他编辑者修改。请刷新后再提交。",
                        Some(project.summary.revision),
                        Some(current.version),
                        Some(command.task_id.clone()),
                    );
                }

                let unchanged = current.title == command.title.trim()
                    && current.notes == command.notes.trim()
                    && current.status == command.status
                    && current.priority == command.priority
                    && current.assignee_id == command.assignee_id
                    && current.due_date == command.due_date
                    && current.position == command.position;
                if unchanged {
                    return self.success(project_index, &envelope.request_id, Vec::new());
                }

                let history_id = self.allocate_id("history");
                let audit_id = self.allocate_id("audit");
                let timestamp = now_timestamp();
                let project = &mut self.projects[project_index];
                project.summary.revision += 1;
                let revision = project.summary.revision;
                let task = &mut project.tasks[task_index];
                task.title = command.title.trim().to_string();
                task.notes = command.notes.trim().to_string();
                task.status = command.status;
                task.priority = command.priority;
                task.assignee_id = command.assignee_id.clone();
                task.due_date = command.due_date;
                task.position = command.position;
                task.version += 1;
                task.updated_at = timestamp.clone();
                task.updated_by = envelope.actor_id.clone();
                task.history.push(TaskHistoryEntry {
                    id: history_id,
                    revision,
                    action: "updated".into(),
                    summary: "更新任务字段".into(),
                    actor_id: envelope.actor_id.clone(),
                    occurred_at: timestamp.clone(),
                });
                trim_task_history(task);
                project.audit.push(ProjectAuditEntry {
                    id: audit_id,
                    revision,
                    action: "updated".into(),
                    summary: format!("更新任务「{}」", task.title),
                    task_id: Some(command.task_id.clone()),
                    actor_id: envelope.actor_id.clone(),
                    occurred_at: timestamp,
                });
                trim_audit(project);
                self.success(
                    project_index,
                    &envelope.request_id,
                    vec![command.task_id.clone()],
                )
            }
            TaskCommand::DeleteTask {
                task_id,
                expected_task_version,
            } => {
                let project = &self.projects[project_index];
                let Some(task_index) = project.tasks.iter().position(|task| task.id == *task_id)
                else {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "task_not_found",
                        "任务不存在。",
                        Some(project.summary.revision),
                        None,
                        Some(task_id.clone()),
                    );
                };
                let current = &project.tasks[task_index];
                if current.version != *expected_task_version {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "version_conflict",
                        "任务已被其他编辑者修改。请刷新后再删除。",
                        Some(project.summary.revision),
                        Some(current.version),
                        Some(task_id.clone()),
                    );
                }

                let audit_id = self.allocate_id("audit");
                let timestamp = now_timestamp();
                let project = &mut self.projects[project_index];
                let removed = project.tasks.remove(task_index);
                project.summary.revision += 1;
                project.audit.push(ProjectAuditEntry {
                    id: audit_id,
                    revision: project.summary.revision,
                    action: "deleted".into(),
                    summary: format!("删除任务「{}」", removed.title),
                    task_id: Some(removed.id.clone()),
                    actor_id: envelope.actor_id.clone(),
                    occurred_at: timestamp,
                });
                trim_audit(project);
                self.success(project_index, &envelope.request_id, vec![removed.id])
            }
            TaskCommand::MoveTask(command) => {
                if let Err(message) = self.validate_assignee(command.assignee_id.as_deref()) {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "invalid_command",
                        message,
                        None,
                        None,
                        None,
                    );
                }

                let project = &self.projects[project_index];
                let Some(task_index) = project
                    .tasks
                    .iter()
                    .position(|task| task.id == command.task_id)
                else {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "task_not_found",
                        "任务不存在。",
                        Some(project.summary.revision),
                        None,
                        Some(command.task_id.clone()),
                    );
                };
                let current = &project.tasks[task_index];
                if current.version != command.expected_task_version {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "version_conflict",
                        "任务已被其他编辑者移动。请刷新后再移动。",
                        Some(project.summary.revision),
                        Some(current.version),
                        Some(command.task_id.clone()),
                    );
                }

                let unchanged = current.assignee_id == command.assignee_id
                    && current.due_date == command.due_date
                    && current.position == command.position;
                if unchanged {
                    return self.success(project_index, &envelope.request_id, Vec::new());
                }

                let history_id = self.allocate_id("history");
                let audit_id = self.allocate_id("audit");
                let timestamp = now_timestamp();
                let project = &mut self.projects[project_index];
                project.summary.revision += 1;
                let revision = project.summary.revision;
                let task = &mut project.tasks[task_index];
                task.assignee_id = command.assignee_id.clone();
                task.due_date = command.due_date;
                task.position = command.position;
                task.version += 1;
                task.updated_at = timestamp.clone();
                task.updated_by = envelope.actor_id.clone();
                task.history.push(TaskHistoryEntry {
                    id: history_id,
                    revision,
                    action: "moved".into(),
                    summary: "移动任务".into(),
                    actor_id: envelope.actor_id.clone(),
                    occurred_at: timestamp.clone(),
                });
                trim_task_history(task);
                project.audit.push(ProjectAuditEntry {
                    id: audit_id,
                    revision,
                    action: "moved".into(),
                    summary: format!("移动任务「{}」", task.title),
                    task_id: Some(command.task_id.clone()),
                    actor_id: envelope.actor_id.clone(),
                    occurred_at: timestamp,
                });
                trim_audit(project);
                self.success(
                    project_index,
                    &envelope.request_id,
                    vec![command.task_id.clone()],
                )
            }
            TaskCommand::SetTasksStatus(command) => {
                if command.items.is_empty() {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "invalid_command",
                        "批量操作至少需要一个任务。",
                        None,
                        None,
                        None,
                    );
                }
                let unique_ids: HashSet<&str> = command
                    .items
                    .iter()
                    .map(|item| item.task_id.as_str())
                    .collect();
                if unique_ids.len() != command.items.len() {
                    return self.failure(
                        project_id,
                        &envelope.request_id,
                        "invalid_command",
                        "批量操作包含重复任务。",
                        None,
                        None,
                        None,
                    );
                }

                let project = &self.projects[project_index];
                let mut indices = Vec::with_capacity(command.items.len());
                for item in &command.items {
                    let Some(index) = project
                        .tasks
                        .iter()
                        .position(|task| task.id == item.task_id)
                    else {
                        return self.failure(
                            project_id,
                            &envelope.request_id,
                            "task_not_found",
                            "批量操作包含不存在的任务。",
                            Some(project.summary.revision),
                            None,
                            Some(item.task_id.clone()),
                        );
                    };
                    let current = &project.tasks[index];
                    if current.version != item.expected_task_version {
                        return self.failure(
                            project_id,
                            &envelope.request_id,
                            "version_conflict",
                            "批量操作已取消。至少一个任务已被其他编辑者修改。",
                            Some(project.summary.revision),
                            Some(current.version),
                            Some(item.task_id.clone()),
                        );
                    }
                    indices.push(index);
                }

                let changed_indices: Vec<usize> = indices
                    .into_iter()
                    .filter(|index| project.tasks[*index].status != command.status)
                    .collect();
                if changed_indices.is_empty() {
                    return self.success(project_index, &envelope.request_id, Vec::new());
                }

                let history_ids: Vec<String> = changed_indices
                    .iter()
                    .map(|_| self.allocate_id("history"))
                    .collect();
                let audit_id = self.allocate_id("audit");
                let timestamp = now_timestamp();
                let project = &mut self.projects[project_index];
                project.summary.revision += 1;
                let revision = project.summary.revision;
                let mut affected = Vec::with_capacity(changed_indices.len());
                for (history_id, index) in history_ids.into_iter().zip(changed_indices) {
                    let task = &mut project.tasks[index];
                    task.status = command.status;
                    task.version += 1;
                    task.updated_at = timestamp.clone();
                    task.updated_by = envelope.actor_id.clone();
                    task.history.push(TaskHistoryEntry {
                        id: history_id,
                        revision,
                        action: "status_changed".into(),
                        summary: format!("状态改为{}", command.status.label()),
                        actor_id: envelope.actor_id.clone(),
                        occurred_at: timestamp.clone(),
                    });
                    trim_task_history(task);
                    affected.push(task.id.clone());
                }
                project.audit.push(ProjectAuditEntry {
                    id: audit_id,
                    revision,
                    action: "batch_status_changed".into(),
                    summary: format!("将 {} 个任务改为{}", affected.len(), command.status.label()),
                    task_id: None,
                    actor_id: envelope.actor_id.clone(),
                    occurred_at: timestamp,
                });
                trim_audit(project);
                self.success(project_index, &envelope.request_id, affected)
            }
        }
    }

    fn validate_fields(
        &self,
        title: &str,
        notes: &str,
        assignee_id: Option<&str>,
    ) -> Result<(), &'static str> {
        let title = title.trim();
        if title.is_empty() {
            return Err("任务标题不能为空。");
        }
        if title.chars().count() > 200 {
            return Err("任务标题不能超过 200 个字符。");
        }
        if notes.chars().count() > 20_000 {
            return Err("任务说明不能超过 20000 个字符。");
        }
        self.validate_assignee(assignee_id)
    }

    fn validate_assignee(&self, assignee_id: Option<&str>) -> Result<(), &'static str> {
        if let Some(id) = assignee_id
            && !self.people.iter().any(|person| person.id == id)
        {
            return Err("负责人不存在。");
        }
        Ok(())
    }

    fn snapshot_for(&self, project: &ProjectState) -> ProjectSnapshot {
        let members: HashSet<&str> = project
            .summary
            .member_ids
            .iter()
            .map(String::as_str)
            .collect();
        ProjectSnapshot {
            project: project.summary.clone(),
            people: self
                .people
                .iter()
                .filter(|person| members.contains(person.id.as_str()))
                .cloned()
                .collect(),
            tasks: project.tasks.clone(),
            audit: project.audit.clone(),
        }
    }

    fn success(
        &mut self,
        project_index: usize,
        request_id: &str,
        affected_task_ids: Vec<String>,
    ) -> CommandResponse {
        let snapshot = self.snapshot_for(&self.projects[project_index]);
        let response =
            CommandResponse::success(request_id.to_string(), snapshot.clone(), affected_task_ids);
        self.processed.insert(
            (snapshot.project.id.clone(), request_id.to_string()),
            response.clone(),
        );
        response
    }

    #[allow(clippy::too_many_arguments)]
    fn failure(
        &mut self,
        project_id: &str,
        request_id: &str,
        code: &str,
        message: &str,
        current_revision: Option<u64>,
        current_task_version: Option<u64>,
        task_id: Option<String>,
    ) -> CommandResponse {
        let response = CommandResponse::failure(
            request_id.to_string(),
            CommandError {
                code: code.to_string(),
                message: message.to_string(),
                current_revision,
                current_task_version,
                task_id,
            },
        );
        self.processed.insert(
            (project_id.to_string(), request_id.to_string()),
            response.clone(),
        );
        response
    }

    fn allocate_id(&mut self, prefix: &str) -> String {
        self.next_id += 1;
        format!("{prefix}-{}", self.next_id)
    }

    #[allow(clippy::too_many_arguments)]
    fn seed_task(
        &mut self,
        project_index: usize,
        id: &str,
        title: &str,
        notes: &str,
        status: TaskStatus,
        priority: TaskPriority,
        assignee_id: Option<&str>,
        due_date: chrono::NaiveDate,
        position: i64,
        timestamp: &str,
    ) {
        let project = &mut self.projects[project_index];
        let actor_id = assignee_id.unwrap_or("person-mia").to_string();
        let history = TaskHistoryEntry {
            id: format!("history-seed-{id}"),
            revision: project.summary.revision,
            action: "seeded".into(),
            summary: "载入演示任务".into(),
            actor_id: actor_id.clone(),
            occurred_at: timestamp.to_string(),
        };
        project.tasks.push(TaskItem {
            id: id.into(),
            project_id: project.summary.id.clone(),
            title: title.into(),
            notes: notes.into(),
            status,
            priority,
            assignee_id: assignee_id.map(str::to_string),
            due_date,
            position,
            version: 1,
            updated_at: timestamp.into(),
            updated_by: actor_id,
            history: vec![history],
        });
        project.audit.push(ProjectAuditEntry {
            id: format!("audit-seed-{id}"),
            revision: project.summary.revision,
            action: "seeded".into(),
            summary: format!("载入任务「{title}」"),
            task_id: Some(id.into()),
            actor_id: "person-mia".into(),
            occurred_at: timestamp.into(),
        });
    }
}

fn now_timestamp() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true)
}

fn trim_task_history(task: &mut TaskItem) {
    if task.history.len() > 50 {
        let remove_count = task.history.len() - 50;
        task.history.drain(0..remove_count);
    }
}

fn trim_audit(project: &mut ProjectState) {
    if project.audit.len() > 100 {
        let remove_count = project.audit.len() - 100;
        project.audit.drain(0..remove_count);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        CreateTaskCommand, MoveTaskCommand, SetTasksStatusCommand, TaskVersionRef,
        UpdateTaskCommand,
    };

    fn envelope(request_id: &str, expected_revision: u64, command: TaskCommand) -> CommandEnvelope {
        CommandEnvelope {
            request_id: request_id.into(),
            expected_revision,
            actor_id: "person-mia".into(),
            command,
        }
    }

    #[test]
    fn projects_are_isolated() {
        let store = KshiftStore::new();
        let focus = store.snapshot("project-focus-2026").unwrap();
        let customer = store.snapshot("project-customer").unwrap();
        assert!(
            focus
                .tasks
                .iter()
                .all(|task| task.project_id == focus.project.id)
        );
        assert!(
            customer
                .tasks
                .iter()
                .all(|task| task.project_id == customer.project.id)
        );
        assert_ne!(focus.project.id, customer.project.id);
    }

    #[test]
    fn create_update_and_conflict_are_audited() {
        let mut store = KshiftStore::new();
        let initial = store.snapshot("project-focus-2026").unwrap();
        let due_date = Local::now().date_naive();
        let created = store.execute(
            "project-focus-2026",
            &envelope(
                "request-create",
                initial.project.revision,
                TaskCommand::CreateTask(CreateTaskCommand {
                    title: " 写测试 ".into(),
                    notes: "冲突必须显式提示".into(),
                    status: TaskStatus::Todo,
                    priority: TaskPriority::High,
                    assignee_id: Some("person-mia".into()),
                    due_date,
                    position: None,
                }),
            ),
        );
        assert!(created.ok);
        let created_snapshot = created.snapshot.unwrap();
        let task = created_snapshot
            .tasks
            .iter()
            .find(|task| task.title == "写测试")
            .unwrap();
        assert_eq!(task.version, 1);

        let updated = store.execute(
            "project-focus-2026",
            &envelope(
                "request-update-a",
                created_snapshot.project.revision,
                TaskCommand::UpdateTask(UpdateTaskCommand {
                    task_id: task.id.clone(),
                    expected_task_version: task.version,
                    title: "写并发测试".into(),
                    notes: task.notes.clone(),
                    status: TaskStatus::InProgress,
                    priority: task.priority,
                    assignee_id: task.assignee_id.clone(),
                    due_date: task.due_date,
                    position: task.position,
                }),
            ),
        );
        assert!(updated.ok);
        let updated_task = updated
            .snapshot
            .as_ref()
            .unwrap()
            .tasks
            .iter()
            .find(|item| item.id == task.id)
            .unwrap()
            .clone();
        assert_eq!(updated_task.version, 2);

        let conflict = store.execute(
            "project-focus-2026",
            &envelope(
                "request-update-b",
                updated.snapshot.as_ref().unwrap().project.revision,
                TaskCommand::UpdateTask(UpdateTaskCommand {
                    task_id: task.id.clone(),
                    expected_task_version: task.version,
                    title: "静默覆盖".into(),
                    notes: task.notes.clone(),
                    status: TaskStatus::Done,
                    priority: task.priority,
                    assignee_id: task.assignee_id.clone(),
                    due_date: task.due_date,
                    position: task.position,
                }),
            ),
        );
        assert!(!conflict.ok);
        assert_eq!(conflict.error.unwrap().code, "version_conflict");
        let after = store.snapshot("project-focus-2026").unwrap();
        let current = after.tasks.iter().find(|item| item.id == task.id).unwrap();
        assert_eq!(current.title, "写并发测试");
        assert_eq!(current.version, 2);
        assert!(
            current
                .history
                .iter()
                .any(|entry| entry.action == "updated")
        );
    }

    #[test]
    fn stale_project_revision_is_rejected() {
        let mut store = KshiftStore::new();
        let initial = store.snapshot("project-focus-2026").unwrap();
        let response = store.execute(
            "project-focus-2026",
            &envelope(
                "request-stale",
                initial.project.revision.saturating_sub(1),
                TaskCommand::MoveTask(MoveTaskCommand {
                    task_id: initial.tasks[0].id.clone(),
                    expected_task_version: initial.tasks[0].version,
                    assignee_id: Some("person-noah".into()),
                    due_date: initial.tasks[0].due_date,
                    position: 1,
                }),
            ),
        );
        assert!(!response.ok);
        assert_eq!(response.error.unwrap().code, "revision_conflict");
    }

    #[test]
    fn batch_update_is_atomic() {
        let mut store = KshiftStore::new();
        let initial = store.snapshot("project-focus-2026").unwrap();
        let first = initial.tasks[0].clone();
        let second = initial.tasks[1].clone();
        let response = store.execute(
            "project-focus-2026",
            &envelope(
                "request-batch",
                initial.project.revision,
                TaskCommand::SetTasksStatus(SetTasksStatusCommand {
                    items: vec![
                        TaskVersionRef {
                            task_id: first.id.clone(),
                            expected_task_version: first.version,
                        },
                        TaskVersionRef {
                            task_id: second.id.clone(),
                            expected_task_version: second.version + 1,
                        },
                    ],
                    status: TaskStatus::Done,
                }),
            ),
        );
        assert!(!response.ok);
        let after = store.snapshot("project-focus-2026").unwrap();
        assert_eq!(
            after
                .tasks
                .iter()
                .find(|task| task.id == first.id)
                .unwrap()
                .status,
            first.status
        );
        assert_eq!(
            after
                .tasks
                .iter()
                .find(|task| task.id == second.id)
                .unwrap()
                .status,
            second.status
        );
    }

    #[test]
    fn request_id_is_idempotent() {
        let mut store = KshiftStore::new();
        let initial = store.snapshot("project-focus-2026").unwrap();
        let command = envelope(
            "request-idempotent",
            initial.project.revision,
            TaskCommand::SetTasksStatus(SetTasksStatusCommand {
                items: vec![TaskVersionRef {
                    task_id: initial.tasks[0].id.clone(),
                    expected_task_version: initial.tasks[0].version,
                }],
                status: TaskStatus::Done,
            }),
        );
        let first = store.execute("project-focus-2026", &command);
        let second = store.execute("project-focus-2026", &command);
        assert_eq!(first, second);
        let after = store.snapshot("project-focus-2026").unwrap();
        assert_eq!(after.project.revision, initial.project.revision + 1);
    }
}
