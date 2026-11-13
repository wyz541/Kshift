use chrono::NaiveDate;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Todo,
    InProgress,
    Blocked,
    Done,
}

impl TaskStatus {
    pub fn label(self) -> &'static str {
        match self {
            Self::Todo => "待处理",
            Self::InProgress => "进行中",
            Self::Blocked => "受阻",
            Self::Done => "已完成",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum TaskPriority {
    Low,
    Medium,
    High,
    Urgent,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Person {
    pub id: String,
    pub name: String,
    pub initials: String,
    pub color_hex: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProjectSummary {
    pub id: String,
    pub name: String,
    pub code: String,
    pub color_hex: String,
    pub member_ids: Vec<String>,
    pub revision: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TaskHistoryEntry {
    pub id: String,
    pub revision: u64,
    pub action: String,
    pub summary: String,
    pub actor_id: String,
    pub occurred_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProjectAuditEntry {
    pub id: String,
    pub revision: u64,
    pub action: String,
    pub summary: String,
    pub task_id: Option<String>,
    pub actor_id: String,
    pub occurred_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TaskItem {
    pub id: String,
    pub project_id: String,
    pub title: String,
    pub notes: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub assignee_id: Option<String>,
    pub due_date: NaiveDate,
    pub position: i64,
    pub version: u64,
    pub updated_at: String,
    pub updated_by: String,
    pub history: Vec<TaskHistoryEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProjectSnapshot {
    pub project: ProjectSummary,
    pub people: Vec<Person>,
    pub tasks: Vec<TaskItem>,
    pub audit: Vec<ProjectAuditEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TaskVersionRef {
    pub task_id: String,
    pub expected_task_version: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum TaskCommand {
    CreateTask(CreateTaskCommand),
    UpdateTask(UpdateTaskCommand),
    DeleteTask {
        task_id: String,
        expected_task_version: u64,
    },
    MoveTask(MoveTaskCommand),
    SetTasksStatus(SetTasksStatusCommand),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CreateTaskCommand {
    pub title: String,
    pub notes: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub assignee_id: Option<String>,
    pub due_date: NaiveDate,
    pub position: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct UpdateTaskCommand {
    pub task_id: String,
    pub expected_task_version: u64,
    pub title: String,
    pub notes: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub assignee_id: Option<String>,
    pub due_date: NaiveDate,
    pub position: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MoveTaskCommand {
    pub task_id: String,
    pub expected_task_version: u64,
    pub assignee_id: Option<String>,
    pub due_date: NaiveDate,
    pub position: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SetTasksStatusCommand {
    pub items: Vec<TaskVersionRef>,
    pub status: TaskStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CommandEnvelope {
    pub request_id: String,
    pub expected_revision: u64,
    pub actor_id: String,
    pub command: TaskCommand,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CommandError {
    pub code: String,
    pub message: String,
    pub current_revision: Option<u64>,
    pub current_task_version: Option<u64>,
    pub task_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CommandResponse {
    pub ok: bool,
    pub request_id: String,
    pub snapshot: Option<ProjectSnapshot>,
    pub affected_task_ids: Vec<String>,
    pub error: Option<CommandError>,
}

impl CommandResponse {
    pub fn success(
        request_id: String,
        snapshot: ProjectSnapshot,
        affected_task_ids: Vec<String>,
    ) -> Self {
        Self {
            ok: true,
            request_id,
            snapshot: Some(snapshot),
            affected_task_ids,
            error: None,
        }
    }

    pub fn failure(request_id: String, error: CommandError) -> Self {
        Self {
            ok: false,
            request_id,
            snapshot: None,
            affected_task_ids: Vec::new(),
            error: Some(error),
        }
    }
}
