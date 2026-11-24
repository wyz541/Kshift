//! Windows task-editor state and typed update-command projection.
//!
//! This module owns only UI drafts and JSON envelopes. Domain validation,
//! authorization, revision checks and persistence remain in the Rust client
//! and server. Keeping this layer platform-neutral lets the Windows shell stay
//! a thin gpui adapter and lets command/conflict behavior run in normal tests.

use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::model::{Priority, Status, Task};

/// Where the current Windows snapshot came from.
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum DataSource {
    /// A local snapshot fixture. The editor is read-only.
    Fixture,
    /// A live FFI-backed server session. Editing is available.
    Server,
}

impl DataSource {
    /// Whether the UI may submit a command for this source.
    pub fn can_edit(self) -> bool {
        matches!(self, Self::Server)
    }

    /// Short label for the schedule subtitle.
    pub fn label(self) -> &'static str {
        match self {
            Self::Fixture => "只读 fixture",
            Self::Server => "server 已连接",
        }
    }
}

/// Editable subset of one task.
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct TaskDraft {
    /// Task identity.
    pub task_id: String,
    /// Version the update is based on.
    pub expected_entity_version: u64,
    /// Title.
    pub title: String,
    /// Markdown description.
    pub description_markdown: String,
    /// Status.
    pub status: Status,
    /// Priority.
    pub priority: Priority,
    /// Assigned member identifiers.
    pub assignee_ids: Vec<String>,
    /// Planned natural date in `YYYY-MM-DD`.
    pub planned_on: String,
}

impl TaskDraft {
    /// Build a draft from the current task projection.
    pub fn from_task(task: &Task) -> Self {
        Self {
            task_id: task.id.clone(),
            expected_entity_version: task.version,
            title: task.title.clone(),
            description_markdown: task.description_markdown.clone(),
            status: task.status,
            priority: task.priority,
            assignee_ids: task.assignee_ids.clone(),
            planned_on: task.planned_on.clone(),
        }
    }

    /// Add or remove one assignee while preserving the remaining order.
    pub fn toggle_assignee(&mut self, user_id: &str) {
        if let Some(index) = self
            .assignee_ids
            .iter()
            .position(|assignee| assignee == user_id)
        {
            self.assignee_ids.remove(index);
        } else {
            self.assignee_ids.push(user_id.to_owned());
        }
    }

    /// Return the text for one editable field.
    pub fn text_field(&self, field: TextField) -> &str {
        match field {
            TextField::Title => &self.title,
            TextField::Description => &self.description_markdown,
            TextField::PlannedOn => &self.planned_on,
        }
    }

    /// Return one editable text field mutably.
    pub fn text_field_mut(&mut self, field: TextField) -> &mut String {
        match field {
            TextField::Title => &mut self.title,
            TextField::Description => &mut self.description_markdown,
            TextField::PlannedOn => &mut self.planned_on,
        }
    }

    /// Project one typed `update_task` command.
    ///
    /// Only fields rendered by the Windows editor are set. Optional fields such
    /// as `starts_on`, `due_on`, `tags`, parent and dependencies stay omitted,
    /// which maps to `Maybe::Unset` in `kshift-ffi`. That prevents an edit from
    /// clearing data the Windows editor does not display.
    pub fn update_command_json(
        &self,
        project_id: &str,
        expected_project_revision: u64,
        client_id: &str,
        command_id: &str,
    ) -> Result<String, String> {
        let payload = json!({
            "client_id": client_id,
            "command_id": command_id,
            "project_id": project_id,
            "expected_project_revision": expected_project_revision,
            "command": {
                "type": "update_task",
                "value": {
                    "task_id": self.task_id,
                    "expected_entity_version": self.expected_entity_version,
                    "title": self.title,
                    "description_markdown": self.description_markdown,
                    "status": status_name(self.status),
                    "priority": priority_name(self.priority),
                    "assignee_ids": self.assignee_ids,
                    "planned_on": self.planned_on
                }
            }
        });
        serde_json::to_string(&payload).map_err(|error| error.to_string())
    }
}

/// One text field rendered by the editor.
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum TextField {
    /// Task title.
    Title,
    /// Markdown description.
    Description,
    /// Planned date.
    PlannedOn,
}

impl TextField {
    /// Next focus target after Tab.
    pub fn next(self) -> Self {
        match self {
            Self::Title => Self::Description,
            Self::Description => Self::PlannedOn,
            Self::PlannedOn => Self::Title,
        }
    }
}

/// Successful typed-command projection.
#[derive(Debug, Clone, Deserialize, Eq, PartialEq)]
pub struct CommandOutcome {
    /// Applied command identity.
    pub command_id: String,
    /// New project revision.
    pub revision: u64,
}

impl CommandOutcome {
    /// Parse the host command-outcome JSON.
    pub fn parse(value: &str) -> Result<Self, String> {
        serde_json::from_str(value).map_err(|error| format!("invalid command outcome: {error}"))
    }
}

/// Host/client command error projection, including conflict details.
#[derive(Debug, Clone, Deserialize, Eq, PartialEq)]
pub struct CommandFailure {
    /// Stable error code from `kshift-ffi`.
    #[serde(default = "unknown_error_code")]
    pub code: String,
    /// Bounded, UI-safe message.
    #[serde(default = "unknown_error_message")]
    pub message: String,
    /// Whether retrying may succeed.
    #[serde(default)]
    pub retryable: bool,
    /// Latest project revision reported by the server.
    #[serde(default)]
    pub current_revision: Option<u64>,
    /// Conflicting entity identity.
    #[serde(default)]
    pub entity_id: Option<String>,
    /// Latest entity version reported by the server.
    #[serde(default)]
    pub entity_version: Option<u64>,
}

impl CommandFailure {
    /// Parse one host error JSON string.
    pub fn parse(value: &str) -> Self {
        serde_json::from_str(value).unwrap_or_else(|_| Self {
            code: "protocol_error".to_owned(),
            message: value.to_owned(),
            retryable: false,
            current_revision: None,
            entity_id: None,
            entity_version: None,
        })
    }

    /// Whether this failure is an optimistic-concurrency conflict.
    pub fn is_conflict(&self) -> bool {
        self.code == "conflict"
    }
}

/// New identifiers for one command submission.
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct CommandIds {
    /// Stable client identity for the UI process.
    pub client_id: String,
    /// Unique command identity for this submission.
    pub command_id: String,
}

impl CommandIds {
    /// Create a stable client identity.
    pub fn client_id() -> String {
        Uuid::new_v4().to_string()
    }

    /// Create identifiers for one submission from a stable client identity.
    pub fn next(client_id: &str) -> Self {
        Self {
            client_id: client_id.to_owned(),
            command_id: Uuid::new_v4().to_string(),
        }
    }
}

/// Insert typed text at a UTF-8-safe cursor.
pub fn insert_text(value: &mut String, cursor: &mut usize, text: &str) {
    let offset = clamp_boundary(value, *cursor);
    value.insert_str(offset, text);
    *cursor = offset + text.len();
}

/// Remove the character before the cursor.
pub fn backspace(value: &mut String, cursor: &mut usize) {
    let offset = clamp_boundary(value, *cursor);
    let Some((previous, _)) = value[..offset].char_indices().next_back() else {
        return;
    };
    value.remove(previous);
    *cursor = previous;
}

/// Remove the character at the cursor.
pub fn delete(value: &mut String, cursor: &mut usize) {
    let offset = clamp_boundary(value, *cursor);
    if offset < value.len() {
        value.remove(offset);
    }
}

/// Move the cursor one character left.
pub fn move_left(value: &str, cursor: &mut usize) {
    let offset = clamp_boundary(value, *cursor);
    if let Some((previous, _)) = value[..offset].char_indices().next_back() {
        *cursor = previous;
    }
}

/// Move the cursor one character right.
pub fn move_right(value: &str, cursor: &mut usize) {
    let offset = clamp_boundary(value, *cursor);
    if let Some((next, _)) = value[offset..].char_indices().nth(1) {
        *cursor = offset + next;
    } else {
        *cursor = value.len();
    }
}

/// Move the cursor to the beginning.
pub fn move_home(cursor: &mut usize) {
    *cursor = 0;
}

/// Move the cursor to the end.
pub fn move_end(value: &str, cursor: &mut usize) {
    *cursor = value.len();
}

/// Split text at the cursor for rendering a visible caret.
pub fn cursor_parts(value: &str, cursor: usize) -> (&str, &str) {
    let offset = clamp_boundary(value, cursor);
    (&value[..offset], &value[offset..])
}

fn clamp_boundary(value: &str, cursor: usize) -> usize {
    let mut offset = cursor.min(value.len());
    while !value.is_char_boundary(offset) {
        offset -= 1;
    }
    offset
}

fn status_name(status: Status) -> &'static str {
    match status {
        Status::Todo => "todo",
        Status::InProgress => "in_progress",
        Status::Blocked => "blocked",
        Status::Done => "done",
    }
}

fn priority_name(priority: Priority) -> &'static str {
    match priority {
        Priority::Low => "low",
        Priority::Medium => "medium",
        Priority::High => "high",
        Priority::Urgent => "urgent",
    }
}

fn unknown_error_code() -> String {
    "unknown".to_owned()
}

fn unknown_error_message() -> String {
    "command failed".to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    fn task() -> Task {
        Task {
            id: "aaaaaaaa-0000-4000-8000-000000000001".to_owned(),
            title: "Ship brief".to_owned(),
            description_markdown: "Publish it.".to_owned(),
            status: Status::InProgress,
            priority: Priority::Urgent,
            assignee_ids: vec!["11111111-1111-4111-8111-111111111111".to_owned()],
            planned_on: "2026-11-23".to_owned(),
            starts_on: Some("2026-11-23".to_owned()),
            due_on: Some("2026-11-25".to_owned()),
            tags: vec!["launch".to_owned()],
            version: 3,
        }
    }

    #[test]
    fn draft_preserves_expected_versions_and_fields() {
        let draft = TaskDraft::from_task(&task());
        assert_eq!(draft.expected_entity_version, 3);
        assert_eq!(draft.title, "Ship brief");
        assert_eq!(draft.status, Status::InProgress);
        assert_eq!(draft.priority, Priority::Urgent);
        assert_eq!(draft.planned_on, "2026-11-23");
    }

    #[test]
    fn command_payload_sets_only_editor_fields() {
        let mut draft = TaskDraft::from_task(&task());
        draft.title = "Updated title".to_owned();
        draft.description_markdown = "Updated body".to_owned();
        draft.status = Status::Blocked;
        draft.priority = Priority::High;
        draft.planned_on = "2026-11-24".to_owned();
        let json = draft
            .update_command_json(
                "9f1c2d3e-0000-4000-8000-000000000001",
                12,
                "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                "99999999-8888-4777-8666-555555555555",
            )
            .expect("command JSON");
        let value: Value = serde_json::from_str(&json).expect("valid JSON");
        assert_eq!(value["expected_project_revision"], 12);
        assert_eq!(value["command"]["type"], "update_task");
        let update = &value["command"]["value"];
        assert_eq!(update["expected_entity_version"], 3);
        assert_eq!(update["title"], "Updated title");
        assert_eq!(update["description_markdown"], "Updated body");
        assert_eq!(update["status"], "blocked");
        assert_eq!(update["priority"], "high");
        assert_eq!(update["planned_on"], "2026-11-24");
        assert!(update.get("starts_on").is_none());
        assert!(update.get("due_on").is_none());
        assert!(update.get("tags").is_none());
        assert!(update.get("parent_task_id").is_none());
        assert!(update.get("dependency_task_ids").is_none());
    }

    #[test]
    fn command_outcome_ignores_event_payload() {
        let outcome =
            CommandOutcome::parse(r#"{"command_id":"c","revision":13,"event":{"revision":13}}"#)
                .expect("outcome");
        assert_eq!(outcome.revision, 13);
        assert_eq!(outcome.command_id, "c");
    }

    #[test]
    fn conflict_error_retains_latest_revisions() {
        let failure = CommandFailure::parse(
            r#"{
                "code":"conflict",
                "message":"write conflict",
                "retryable":false,
                "current_revision":14,
                "entity_id":"aaaaaaaa-0000-4000-8000-000000000001",
                "entity_version":5
            }"#,
        );
        assert!(failure.is_conflict());
        assert_eq!(failure.current_revision, Some(14));
        assert_eq!(failure.entity_version, Some(5));
    }

    #[test]
    fn malformed_error_keeps_a_visible_fallback_message() {
        let failure = CommandFailure::parse("not-json");
        assert_eq!(failure.code, "protocol_error");
        assert_eq!(failure.message, "not-json");
        assert!(!failure.retryable);
    }

    #[test]
    fn text_edits_respect_utf8_boundaries() {
        let mut value = "ab计划".to_owned();
        let mut cursor = value.len();
        insert_text(&mut value, &mut cursor, "✓");
        assert_eq!(value, "ab计划✓");
        backspace(&mut value, &mut cursor);
        assert_eq!(value, "ab计划");
        move_left(&value, &mut cursor);
        backspace(&mut value, &mut cursor);
        assert_eq!(value, "ab划");
        move_home(&mut cursor);
        delete(&mut value, &mut cursor);
        assert_eq!(value, "b划");
        move_end(&value, &mut cursor);
        insert_text(&mut value, &mut cursor, "定");
        assert_eq!(value, "b划定");
    }

    #[test]
    fn assignee_toggle_preserves_order_and_removes_existing() {
        let mut draft = TaskDraft::from_task(&task());
        draft.toggle_assignee("22222222-2222-4222-8222-222222222222");
        assert_eq!(draft.assignee_ids.len(), 2);
        draft.toggle_assignee("11111111-1111-4111-8111-111111111111");
        assert_eq!(
            draft.assignee_ids,
            vec!["22222222-2222-4222-8222-222222222222"]
        );
    }
}
