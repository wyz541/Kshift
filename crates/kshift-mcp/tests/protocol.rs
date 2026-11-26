use std::collections::HashMap;

use async_trait::async_trait;
use chrono::{TimeZone, Utc};
use domain::{
    Project, ProjectMember, ProjectRole, ProjectSnapshot, Task, TaskPriority, TaskStatus,
};
use kshift_client::ProjectSummary;
use kshift_mcp::{McpBackend, McpError, McpServer};
use serde_json::{json, Value};
use uuid::Uuid;

#[derive(Clone)]
struct FakeBackend {
    project_id: Uuid,
    summary: ProjectSummary,
    snapshot: ProjectSnapshot,
}

#[async_trait]
impl McpBackend for FakeBackend {
    async fn list_projects(&self) -> Result<Vec<ProjectSummary>, McpError> {
        Ok(vec![self.summary.clone()])
    }

    async fn get_snapshot(&self, project_id: Uuid) -> Result<ProjectSnapshot, McpError> {
        if project_id == self.project_id {
            Ok(self.snapshot.clone())
        } else {
            Err(McpError::PermissionDenied)
        }
    }
}

fn task(
    project_id: Uuid,
    id: Uuid,
    title: &str,
    parent_task_id: Option<Uuid>,
    dependency_task_ids: &[Uuid],
) -> Task {
    let now = Utc.with_ymd_and_hms(2026, 11, 26, 0, 0, 0).unwrap();
    Task {
        id,
        project_id,
        title: title.to_owned(),
        description_markdown: format!("{title} description"),
        status: TaskStatus::Todo,
        priority: TaskPriority::Medium,
        assignee_ids: Vec::new(),
        planned_on: now.date_naive(),
        starts_on: None,
        due_on: None,
        tags: Vec::new(),
        parent_task_id,
        dependency_task_ids: dependency_task_ids.to_vec(),
        version: 1,
        created_by: Uuid::new_v4(),
        updated_by: Uuid::new_v4(),
        created_at: now,
        updated_at: now,
    }
}

fn fixture() -> FakeBackend {
    let project_id = Uuid::new_v4();
    let parent_id = Uuid::new_v4();
    let child_id = Uuid::new_v4();
    let now = Utc.with_ymd_and_hms(2026, 11, 26, 0, 0, 0).unwrap();
    let snapshot = ProjectSnapshot {
        project: Project {
            id: project_id,
            name: "MCP Project".to_owned(),
            time_zone: "UTC".to_owned(),
            current_revision: 4,
            created_at: now,
            updated_at: now,
        },
        members: vec![ProjectMember {
            user_id: Uuid::new_v4(),
            display_name: "Editor".to_owned(),
            role: ProjectRole::Editor,
        }],
        tasks: vec![
            task(project_id, parent_id, "Parent", None, &[]),
            task(project_id, child_id, "Child", Some(parent_id), &[]),
        ],
        audit: Vec::new(),
        generated_at: now,
    };
    FakeBackend {
        project_id,
        summary: ProjectSummary {
            id: project_id,
            name: "MCP Project".to_owned(),
            time_zone: "UTC".to_owned(),
            current_revision: 4,
        },
        snapshot,
    }
}

async fn call(server: &McpServer<FakeBackend>, id: u64, method: &str, params: Value) -> Value {
    let request = json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": method,
        "params": params
    });
    let response = server
        .handle_line(&request.to_string())
        .await
        .expect("request should return a response");
    serde_json::from_str(&response).expect("response should be JSON")
}

#[tokio::test]
async fn initialize_and_tools_list_are_read_only() {
    let backend = fixture();
    let server = McpServer::new(backend);
    let initialized = call(&server, 1, "initialize", json!({})).await;
    assert_eq!(initialized["result"]["protocolVersion"], "2025-06-18");
    assert!(initialized["result"]["capabilities"]["tools"].is_object());

    let listed = call(&server, 2, "tools/list", json!({})).await;
    let tools = listed["result"]["tools"]
        .as_array()
        .expect("tools should be an array");
    assert!(tools.iter().any(|tool| tool["name"] == "get_mind_map"));
    assert!(!tools.iter().any(|tool| tool["name"] == "create_task"));

    let resources = call(&server, 11, "resources/list", json!({})).await;
    assert_eq!(
        resources["result"]["resources"]
            .as_array()
            .expect("resources should be an array")
            .len(),
        1
    );
}

#[tokio::test]
async fn read_tools_and_mind_map_are_bounded() {
    let backend = fixture();
    let project_id = backend.project_id;
    let server = McpServer::new(backend);

    let overview = call(
        &server,
        3,
        "tools/call",
        json!({"name": "get_project_overview", "arguments": {"project_id": project_id}}),
    )
    .await;
    assert_eq!(
        overview["result"]["structuredContent"]["task_count"],
        Value::from(2)
    );

    let search = call(
        &server,
        4,
        "tools/call",
        json!({"name": "search_tasks", "arguments": {"project_id": project_id, "query": "Child", "limit": 1}}),
    )
    .await;
    assert_eq!(
        search["result"]["structuredContent"]["tasks"]
            .as_array()
            .expect("tasks should be an array")
            .len(),
        1
    );
    assert_eq!(
        search["result"]["structuredContent"]["truncated"],
        Value::Bool(false)
    );

    let mind_map = call(
        &server,
        5,
        "tools/call",
        json!({"name": "get_mind_map", "arguments": {"project_id": project_id, "node_limit": 1}}),
    )
    .await;
    assert_eq!(
        mind_map["result"]["structuredContent"]["nodes"]
            .as_array()
            .expect("nodes should be an array")
            .len(),
        1
    );
    assert_eq!(
        mind_map["result"]["structuredContent"]["truncated"],
        Value::Bool(true)
    );
}

#[tokio::test]
async fn write_tools_and_unauthorized_projects_are_rejected() {
    let backend = fixture();
    let project_id = backend.project_id;
    let server = McpServer::new(backend);

    let write = call(
        &server,
        6,
        "tools/call",
        json!({"name": "create_task", "arguments": {"project_id": project_id}}),
    )
    .await;
    assert_eq!(write["result"]["isError"], Value::Bool(true));
    assert_eq!(
        write["result"]["structuredContent"]["error"]["code"],
        "read_only"
    );

    let denied = call(
        &server,
        7,
        "tools/call",
        json!({"name": "get_project_overview", "arguments": {"project_id": Uuid::new_v4()}}),
    )
    .await;
    assert_eq!(denied["result"]["isError"], Value::Bool(true));
    assert_eq!(
        denied["result"]["structuredContent"]["error"]["code"],
        "permission_denied"
    );
}

#[tokio::test]
async fn resources_read_returns_compact_snapshot_and_mind_map() {
    let backend = fixture();
    let project_id = backend.project_id;
    let server = McpServer::new(backend);

    let projects = call(
        &server,
        8,
        "resources/read",
        json!({"uri": "kshift://projects"}),
    )
    .await;
    let text = projects["result"]["contents"][0]["text"]
        .as_str()
        .expect("resource text should be a string");
    let value: Value = serde_json::from_str(text).expect("resource text should be JSON");
    assert_eq!(
        value["projects"].as_array().expect("projects array").len(),
        1
    );

    let snapshot = call(
        &server,
        9,
        "resources/read",
        json!({"uri": format!("kshift://project/{project_id}/snapshot")}),
    )
    .await;
    assert!(snapshot["result"]["contents"][0]["text"]
        .as_str()
        .expect("snapshot text")
        .contains("MCP Project"));

    let mind_map = call(
        &server,
        10,
        "resources/read",
        json!({"uri": format!("kshift://project/{project_id}/mind-map")}),
    )
    .await;
    let text = mind_map["result"]["contents"][0]["text"]
        .as_str()
        .expect("mind-map text");
    let value: Value = serde_json::from_str(text).expect("mind-map text should be JSON");
    assert_eq!(value["nodes"].as_array().expect("nodes array").len(), 2);
}

#[test]
fn fixture_is_project_scoped() {
    let backend = fixture();
    assert_eq!(backend.snapshot.tasks.len(), 2);
    let mut ids = HashMap::new();
    for task in &backend.snapshot.tasks {
        ids.insert(task.id, task.project_id);
    }
    assert!(ids
        .values()
        .all(|project_id| *project_id == backend.project_id));
}
