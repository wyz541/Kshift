//! Snapshot JSON projections shared with the macOS host.
//!
//! Field names match the `kshift-ffi` JSON projection, which is the
//! `kshift-domain` snapshot serialized with `snake_case` names.

use std::path::Path;

use serde::Deserialize;

/// One project snapshot returned by `kshift-ffi`.
#[derive(Debug, Clone, Deserialize)]
pub struct Snapshot {
    /// Project header.
    pub project: Project,
    /// Project members.
    #[serde(default)]
    pub members: Vec<Member>,
    /// Project tasks.
    #[serde(default)]
    pub tasks: Vec<Task>,
}

/// Project header fields used by the schedule.
#[derive(Debug, Clone, Deserialize)]
pub struct Project {
    /// Stable project identifier.
    #[serde(default)]
    pub id: String,
    /// Display name.
    pub name: String,
    /// IANA time zone. It decides natural dates on the server.
    #[serde(default)]
    pub time_zone: String,
    /// Current project revision.
    #[serde(default)]
    pub current_revision: u64,
}

/// One project member.
#[derive(Debug, Clone, Deserialize)]
pub struct Member {
    /// Stable user identifier.
    pub user_id: String,
    /// Display name.
    pub display_name: String,
    /// Project role.
    #[serde(default)]
    pub role: Role,
}

/// Project role. Defaults to `viewer` when the field is absent.
#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    /// Read-only member.
    #[default]
    Viewer,
    /// Member who can edit tasks.
    Editor,
    /// Member who can manage the project.
    Admin,
}

impl Role {
    /// Short label for the schedule row.
    pub fn label(self) -> &'static str {
        match self {
            Self::Viewer => "只读",
            Self::Editor => "编辑",
            Self::Admin => "管理",
        }
    }
}

/// One task.
#[derive(Debug, Clone, Deserialize)]
pub struct Task {
    /// Stable task identifier.
    pub id: String,
    /// Title.
    pub title: String,
    /// Markdown description. The skeleton does not render it.
    #[serde(default)]
    pub description_markdown: String,
    /// Task status.
    pub status: Status,
    /// Task priority.
    pub priority: Priority,
    /// Assignees. A task can have zero or more.
    #[serde(default)]
    pub assignee_ids: Vec<String>,
    /// Planned natural date in `YYYY-MM-DD`.
    pub planned_on: String,
    /// Optional start date in `YYYY-MM-DD`.
    #[serde(default)]
    pub starts_on: Option<String>,
    /// Optional due date in `YYYY-MM-DD`.
    #[serde(default)]
    pub due_on: Option<String>,
    /// Tags.
    #[serde(default)]
    pub tags: Vec<String>,
    /// Entity version.
    #[serde(default)]
    pub version: u64,
}

/// Task status.
#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    /// Not started.
    Todo,
    /// In progress.
    InProgress,
    /// Blocked.
    Blocked,
    /// Done.
    Done,
}

impl Status {
    /// Chinese label aligned with the macOS host.
    pub fn label(self) -> &'static str {
        match self {
            Self::Todo => "待处理",
            Self::InProgress => "进行中",
            Self::Blocked => "受阻",
            Self::Done => "已完成",
        }
    }
}

/// Task priority.
#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum Priority {
    /// P3.
    Low,
    /// P2.
    Medium,
    /// P1.
    High,
    /// P0.
    Urgent,
}

impl Priority {
    /// Badge text aligned with the macOS host.
    pub fn badge(self) -> &'static str {
        match self {
            Self::Urgent => "P0",
            Self::High => "P1",
            Self::Medium => "P2",
            Self::Low => "P3",
        }
    }
}

/// Parse one snapshot JSON string.
pub fn parse(json: &str) -> Result<Snapshot, serde_json::Error> {
    serde_json::from_str(json)
}

/// Read and parse one snapshot JSON file.
pub fn load(path: impl AsRef<Path>) -> Result<Snapshot, String> {
    let path = path.as_ref();
    let text = std::fs::read_to_string(path)
        .map_err(|error| format!("read {}: {error}", path.display()))?;
    parse(&text).map_err(|error| format!("parse {}: {error}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    const MINIMAL: &str = r#"{
        "project": {"name": "Launch Room", "current_revision": 12},
        "members": [
            {"user_id": "u1", "display_name": "Mia Chen", "role": "editor"}
        ],
        "tasks": [
            {
                "id": "t1",
                "title": "Ship brief",
                "status": "in_progress",
                "priority": "urgent",
                "assignee_ids": ["u1"],
                "planned_on": "2026-11-23"
            }
        ]
    }"#;

    #[test]
    fn parses_the_ffi_projection() {
        let snapshot = parse(MINIMAL).expect("snapshot parses");
        assert_eq!(snapshot.project.name, "Launch Room");
        assert_eq!(snapshot.project.current_revision, 12);
        assert_eq!(snapshot.members.len(), 1);
        assert_eq!(snapshot.members[0].role, Role::Editor);
        assert_eq!(snapshot.tasks.len(), 1);
        assert_eq!(snapshot.tasks[0].status, Status::InProgress);
        assert_eq!(snapshot.tasks[0].priority, Priority::Urgent);
        assert_eq!(snapshot.tasks[0].assignee_ids, ["u1".to_owned()]);
    }

    #[test]
    fn missing_optional_fields_use_defaults() {
        let json = r#"{"project": {"name": "Empty"}}"#;
        let snapshot = parse(json).expect("snapshot parses");
        assert!(snapshot.members.is_empty());
        assert!(snapshot.tasks.is_empty());
        assert_eq!(snapshot.project.current_revision, 0);
    }

    #[test]
    fn role_defaults_to_viewer() {
        let json = r#"{"project":{"name":"P"},"members":[{"user_id":"u","display_name":"U"}]}"#;
        let snapshot = parse(json).expect("snapshot parses");
        assert_eq!(snapshot.members[0].role, Role::Viewer);
    }

    #[test]
    fn labels_match_the_macos_host() {
        assert_eq!(Status::Todo.label(), "待处理");
        assert_eq!(Status::InProgress.label(), "进行中");
        assert_eq!(Status::Blocked.label(), "受阻");
        assert_eq!(Status::Done.label(), "已完成");
        assert_eq!(Priority::Urgent.badge(), "P0");
        assert_eq!(Priority::High.badge(), "P1");
        assert_eq!(Priority::Medium.badge(), "P2");
        assert_eq!(Priority::Low.badge(), "P3");
    }
}
