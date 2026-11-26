//! Minimal MCP stdio JSON-RPC adapter.

use std::collections::HashMap;

use domain::{ProjectSnapshot, Task, TaskPriority, TaskStatus};
use kshift_core::{project_task_mind_map, DEFAULT_MIND_MAP_NODE_LIMIT, MAX_MIND_MAP_NODE_LIMIT};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use uuid::Uuid;

use crate::{McpBackend, McpError};

const PROTOCOL_VERSION: &str = "2025-06-18";
const MAX_LIST_PROJECTS: usize = 100;
const MAX_TASK_SEARCH_LIMIT: usize = 200;

#[derive(Debug, Deserialize)]
struct JsonRpcRequest {
    jsonrpc: Option<String>,
    id: Option<Value>,
    method: String,
    #[serde(default)]
    params: Option<Value>,
}

#[derive(Debug)]
struct JsonRpcError {
    code: i64,
    message: String,
    data: Option<Value>,
}

impl JsonRpcError {
    fn method_not_found(method: &str) -> Self {
        Self {
            code: -32601,
            message: format!("method not found: {method}"),
            data: None,
        }
    }

    fn invalid_params(message: impl Into<String>) -> Self {
        Self {
            code: -32602,
            message: message.into(),
            data: None,
        }
    }

    fn internal(message: impl Into<String>) -> Self {
        Self {
            code: -32603,
            message: message.into(),
            data: None,
        }
    }
}

/// MCP server with a read-only backend.
pub struct McpServer<B> {
    backend: B,
}

impl<B> McpServer<B>
where
    B: McpBackend,
{
    /// Create a server around one backend.
    pub fn new(backend: B) -> Self {
        Self { backend }
    }

    /// Handle one JSON-RPC line and return an optional response line.
    pub async fn handle_line(&self, line: &str) -> Option<String> {
        let line = line.trim();
        if line.is_empty() {
            return None;
        }
        let request = match serde_json::from_str::<JsonRpcRequest>(line) {
            Ok(request) => request,
            Err(error) => {
                return Some(
                    json!({
                        "jsonrpc": "2.0",
                        "id": Value::Null,
                        "error": {
                            "code": -32700,
                            "message": format!("parse error: {error}")
                        }
                    })
                    .to_string(),
                );
            }
        };
        if request.jsonrpc.as_deref() != Some("2.0") {
            return request.id.map(|id| {
                json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": {
                        "code": -32600,
                        "message": "jsonrpc must be 2.0"
                    }
                })
                .to_string()
            });
        }

        let result = self
            .dispatch(&request.method, request.params.as_ref())
            .await;
        let id = request.id?;
        Some(match result {
            Ok(result) => json!({"jsonrpc": "2.0", "id": id, "result": result}).to_string(),
            Err(error) => json!({
                "jsonrpc": "2.0",
                "id": id,
                "error": {
                    "code": error.code,
                    "message": error.message,
                    "data": error.data
                }
            })
            .to_string(),
        })
    }

    async fn dispatch(&self, method: &str, params: Option<&Value>) -> Result<Value, JsonRpcError> {
        match method {
            "initialize" => Ok(json!({
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {
                    "tools": {},
                    "resources": {}
                },
                "serverInfo": {
                    "name": "kshift-mcp",
                    "version": env!("CARGO_PKG_VERSION")
                }
            })),
            "notifications/initialized" => Ok(json!({})),
            "ping" => Ok(json!({})),
            "tools/list" => Ok(json!({"tools": tool_definitions()})),
            "tools/call" => self.call_tool(params).await,
            "resources/list" => Ok(json!({
                "resources": [{
                    "uri": "kshift://projects",
                    "name": "Visible Kshift projects",
                    "description": "Projects visible to the authenticated Kshift identity",
                    "mimeType": "application/json"
                }]
            })),
            "resources/templates/list" => Ok(json!({
                "resourceTemplates": [
                    {
                        "uriTemplate": "kshift://project/{project_id}/snapshot",
                        "name": "Project overview",
                        "description": "Compact project snapshot summary",
                        "mimeType": "application/json"
                    },
                    {
                        "uriTemplate": "kshift://project/{project_id}/mind-map",
                        "name": "Task mind map",
                        "description": "Read-only task graph projection",
                        "mimeType": "application/json"
                    }
                ]
            })),
            "resources/read" => self.read_resource(params).await,
            "prompts/list" => Ok(json!({"prompts": []})),
            _ => Err(JsonRpcError::method_not_found(method)),
        }
    }

    async fn call_tool(&self, params: Option<&Value>) -> Result<Value, JsonRpcError> {
        let params = params.unwrap_or(&Value::Null);
        let name = params
            .get("name")
            .and_then(Value::as_str)
            .ok_or_else(|| JsonRpcError::invalid_params("tools/call params.name is required"))?;
        let arguments = params
            .get("arguments")
            .cloned()
            .unwrap_or_else(|| json!({}));
        match name {
            "list_projects" => self.tool_list_projects().await,
            "get_project_overview" => self.tool_project_overview(&arguments).await,
            "search_tasks" => self.tool_search_tasks(&arguments).await,
            "get_task" => self.tool_get_task(&arguments).await,
            "get_mind_map" => self.tool_get_mind_map(&arguments).await,
            "create_project" | "add_project_member" | "create_task" | "update_task"
            | "delete_task" | "batch_update_tasks" | "set_task_status" => Ok(tool_error(
                McpError::ReadOnly(format!("tool `{name}` is not available in read-only mode")),
            )),
            _ => Ok(tool_error(McpError::InvalidArgument(format!(
                "unknown tool: {name}"
            )))),
        }
    }

    async fn tool_list_projects(&self) -> Result<Value, JsonRpcError> {
        let projects = match self.backend.list_projects().await {
            Ok(projects) => projects,
            Err(error) => return Ok(tool_error(error)),
        };
        let total = projects.len();
        let included = projects.iter().take(MAX_LIST_PROJECTS).collect::<Vec<_>>();
        Ok(tool_ok(json!({
            "projects": included,
            "total": total,
            "truncated": total > included.len()
        })))
    }

    async fn tool_project_overview(&self, arguments: &Value) -> Result<Value, JsonRpcError> {
        let project_id = required_uuid(arguments, "project_id")?;
        let snapshot = match self.backend.get_snapshot(project_id).await {
            Ok(snapshot) => snapshot,
            Err(error) => return Ok(tool_error(error)),
        };
        Ok(tool_ok(project_overview(&snapshot)))
    }

    async fn tool_search_tasks(&self, arguments: &Value) -> Result<Value, JsonRpcError> {
        let project_id = required_uuid(arguments, "project_id")?;
        let query = arguments.get("query").and_then(Value::as_str).unwrap_or("");
        if query.chars().count() > 200 {
            return Ok(tool_error(McpError::InvalidArgument(
                "query must not exceed 200 characters".to_owned(),
            )));
        }
        let query = query.to_lowercase();
        let limit = limit_arg(arguments, "limit", 50, MAX_TASK_SEARCH_LIMIT)?;
        let snapshot = match self.backend.get_snapshot(project_id).await {
            Ok(snapshot) => snapshot,
            Err(error) => return Ok(tool_error(error)),
        };
        let mut matches = snapshot
            .tasks
            .iter()
            .filter(|task| {
                query.is_empty()
                    || task.title.to_lowercase().contains(&query)
                    || task.description_markdown.to_lowercase().contains(&query)
            })
            .collect::<Vec<_>>();
        matches.sort_by_key(|task| task.id);
        let total_matches = matches.len();
        let tasks = matches
            .iter()
            .take(limit)
            .map(|task| task_summary(task))
            .collect::<Vec<_>>();
        Ok(tool_ok(json!({
            "project_id": project_id,
            "revision": snapshot.project.current_revision,
            "query": query,
            "tasks": tasks,
            "total_matches": total_matches,
            "truncated": total_matches > limit
        })))
    }

    async fn tool_get_task(&self, arguments: &Value) -> Result<Value, JsonRpcError> {
        let project_id = required_uuid(arguments, "project_id")?;
        let task_id = required_uuid(arguments, "task_id")?;
        let snapshot = match self.backend.get_snapshot(project_id).await {
            Ok(snapshot) => snapshot,
            Err(error) => return Ok(tool_error(error)),
        };
        let Some(task) = snapshot.tasks.iter().find(|task| task.id == task_id) else {
            return Ok(tool_error(McpError::NotFound(format!(
                "task {task_id} was not found in project"
            ))));
        };
        Ok(tool_ok(task_summary(task)))
    }

    async fn tool_get_mind_map(&self, arguments: &Value) -> Result<Value, JsonRpcError> {
        let project_id = required_uuid(arguments, "project_id")?;
        let limit = limit_arg(
            arguments,
            "node_limit",
            DEFAULT_MIND_MAP_NODE_LIMIT,
            MAX_MIND_MAP_NODE_LIMIT,
        )?;
        let snapshot = match self.backend.get_snapshot(project_id).await {
            Ok(snapshot) => snapshot,
            Err(error) => return Ok(tool_error(error)),
        };
        let projection = project_task_mind_map(&snapshot, limit).map_err(|error| {
            JsonRpcError::internal(format!("mind-map projection failed: {error}"))
        })?;
        Ok(tool_ok(json!(projection)))
    }

    async fn read_resource(&self, params: Option<&Value>) -> Result<Value, JsonRpcError> {
        let params = params.unwrap_or(&Value::Null);
        let uri = params
            .get("uri")
            .and_then(Value::as_str)
            .ok_or_else(|| JsonRpcError::invalid_params("resources/read params.uri is required"))?;
        if uri == "kshift://projects" {
            let projects = self
                .backend
                .list_projects()
                .await
                .map_err(mcp_error_to_rpc)?;
            return Ok(resource_contents(uri, json!({"projects": projects})));
        }
        let Some(rest) = uri.strip_prefix("kshift://project/") else {
            return Err(JsonRpcError::invalid_params(format!(
                "unsupported resource URI: {uri}"
            )));
        };
        let mut parts = rest.split('/');
        let project_id = parse_uuid(parts.next().unwrap_or_default(), "project_id")?;
        let kind = parts.next().unwrap_or_default();
        if parts.next().is_some() {
            return Err(JsonRpcError::invalid_params(format!(
                "invalid resource URI: {uri}"
            )));
        }
        let snapshot = self
            .backend
            .get_snapshot(project_id)
            .await
            .map_err(mcp_error_to_rpc)?;
        let value = match kind {
            "snapshot" => project_overview(&snapshot),
            "mind-map" => json!(
                project_task_mind_map(&snapshot, DEFAULT_MIND_MAP_NODE_LIMIT).map_err(|error| {
                    JsonRpcError::internal(format!("mind-map projection failed: {error}"))
                })?
            ),
            _ => {
                return Err(JsonRpcError::invalid_params(format!(
                    "unsupported resource URI: {uri}"
                )));
            }
        };
        Ok(resource_contents(uri, value))
    }
}

fn tool_definitions() -> Vec<Value> {
    vec![
        json!({
            "name": "list_projects",
            "description": "List projects visible to the authenticated Kshift identity.",
            "inputSchema": {
                "type": "object",
                "properties": {},
                "additionalProperties": false
            }
        }),
        json!({
            "name": "get_project_overview",
            "description": "Read a compact project summary without returning the full snapshot.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_id": {"type": "string", "format": "uuid"}
                },
                "required": ["project_id"],
                "additionalProperties": false
            }
        }),
        json!({
            "name": "search_tasks",
            "description": "Search tasks in one authorized project with bounded results.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_id": {"type": "string", "format": "uuid"},
                    "query": {"type": "string", "maxLength": 200},
                    "limit": {"type": "integer", "minimum": 1, "maximum": 200, "default": 50}
                },
                "required": ["project_id"],
                "additionalProperties": false
            }
        }),
        json!({
            "name": "get_task",
            "description": "Read one task summary from an authorized project.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_id": {"type": "string", "format": "uuid"},
                    "task_id": {"type": "string", "format": "uuid"}
                },
                "required": ["project_id", "task_id"],
                "additionalProperties": false
            }
        }),
        json!({
            "name": "get_mind_map",
            "description": "Read the revision-pinned task graph as a mind-map projection.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_id": {"type": "string", "format": "uuid"},
                    "node_limit": {"type": "integer", "minimum": 1, "maximum": 1000, "default": 256}
                },
                "required": ["project_id"],
                "additionalProperties": false
            }
        }),
    ]
}

fn tool_ok(value: Value) -> Value {
    json!({
        "content": [{"type": "text", "text": value.to_string()}],
        "structuredContent": value,
        "isError": false
    })
}

fn tool_error(error: McpError) -> Value {
    let value = json!({
        "error": {
            "code": error.code(),
            "message": error.to_string(),
            "retryable": error.retryable()
        }
    });
    json!({
        "content": [{"type": "text", "text": value.to_string()}],
        "structuredContent": value,
        "isError": true
    })
}

fn resource_contents(uri: &str, value: Value) -> Value {
    json!({
        "contents": [{
            "uri": uri,
            "mimeType": "application/json",
            "text": value.to_string()
        }]
    })
}

fn project_overview(snapshot: &ProjectSnapshot) -> Value {
    let mut status_counts: HashMap<String, usize> = HashMap::new();
    let mut priority_counts: HashMap<String, usize> = HashMap::new();
    for task in &snapshot.tasks {
        *status_counts
            .entry(status_name(task.status).to_owned())
            .or_default() += 1;
        *priority_counts
            .entry(priority_name(task.priority).to_owned())
            .or_default() += 1;
    }
    json!({
        "project": snapshot.project,
        "revision": snapshot.project.current_revision,
        "generated_at": snapshot.generated_at,
        "member_count": snapshot.members.len(),
        "task_count": snapshot.tasks.len(),
        "status_counts": status_counts,
        "priority_counts": priority_counts
    })
}

fn task_summary(task: &Task) -> Value {
    json!({
        "id": task.id,
        "title": task.title,
        "status": status_name(task.status),
        "priority": priority_name(task.priority),
        "assignee_ids": task.assignee_ids,
        "planned_on": task.planned_on,
        "starts_on": task.starts_on,
        "due_on": task.due_on,
        "parent_task_id": task.parent_task_id,
        "dependency_task_ids": task.dependency_task_ids,
        "version": task.version
    })
}

fn status_name(status: TaskStatus) -> &'static str {
    match status {
        TaskStatus::Todo => "todo",
        TaskStatus::InProgress => "in_progress",
        TaskStatus::Blocked => "blocked",
        TaskStatus::Done => "done",
    }
}

fn priority_name(priority: TaskPriority) -> &'static str {
    match priority {
        TaskPriority::None => "none",
        TaskPriority::Low => "low",
        TaskPriority::Medium => "medium",
        TaskPriority::High => "high",
        TaskPriority::Urgent => "urgent",
    }
}

fn required_uuid(arguments: &Value, key: &str) -> Result<Uuid, JsonRpcError> {
    let value = arguments
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| JsonRpcError::invalid_params(format!("{key} is required")))?;
    parse_uuid(value, key)
}

fn parse_uuid(value: &str, key: &str) -> Result<Uuid, JsonRpcError> {
    Uuid::parse_str(value)
        .map_err(|_| JsonRpcError::invalid_params(format!("{key} must be a UUID")))
}

fn limit_arg(
    arguments: &Value,
    key: &str,
    default: usize,
    maximum: usize,
) -> Result<usize, JsonRpcError> {
    let Some(value) = arguments.get(key) else {
        return Ok(default);
    };
    let Some(value) = value.as_u64() else {
        return Err(JsonRpcError::invalid_params(format!(
            "{key} must be an integer"
        )));
    };
    let value = usize::try_from(value)
        .map_err(|_| JsonRpcError::invalid_params(format!("{key} is too large")))?;
    if value == 0 || value > maximum {
        return Err(JsonRpcError::invalid_params(format!(
            "{key} must be between 1 and {maximum}"
        )));
    }
    Ok(value)
}

fn mcp_error_to_rpc(error: McpError) -> JsonRpcError {
    match error {
        McpError::InvalidArgument(message) => JsonRpcError::invalid_params(message),
        McpError::Unauthenticated => JsonRpcError::invalid_params("authentication is required"),
        McpError::PermissionDenied => JsonRpcError::invalid_params("permission denied"),
        McpError::NotFound(message) => JsonRpcError::invalid_params(message),
        McpError::ReadOnly(message) => JsonRpcError::invalid_params(message),
        McpError::Unavailable(message) => JsonRpcError::internal(message),
        McpError::Cancelled => JsonRpcError::internal("request cancelled"),
        McpError::Internal => JsonRpcError::internal("internal MCP adapter error"),
    }
}

/// Run the MCP server over stdin/stdout until EOF.
pub async fn run_stdio<B>(backend: B) -> anyhow::Result<()>
where
    B: McpBackend,
{
    let server = McpServer::new(backend);
    let stdin = BufReader::new(tokio::io::stdin());
    let mut lines = stdin.lines();
    let mut stdout = tokio::io::stdout();
    while let Some(line) = lines.next_line().await? {
        if let Some(response) = server.handle_line(&line).await {
            stdout.write_all(response.as_bytes()).await?;
            stdout.write_all(b"\n").await?;
            stdout.flush().await?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use kshift_client::ProjectSummary;

    use super::*;

    #[test]
    fn task_summary_uses_stable_names() {
        let task = Task {
            id: Uuid::new_v4(),
            project_id: Uuid::new_v4(),
            title: "Stable".to_owned(),
            description_markdown: String::new(),
            status: TaskStatus::InProgress,
            priority: TaskPriority::High,
            assignee_ids: Vec::new(),
            planned_on: chrono::NaiveDate::from_ymd_opt(2026, 11, 26).unwrap(),
            starts_on: None,
            due_on: None,
            tags: Vec::new(),
            parent_task_id: None,
            dependency_task_ids: Vec::new(),
            version: 3,
            created_by: Uuid::new_v4(),
            updated_by: Uuid::new_v4(),
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };
        let summary = task_summary(&task);
        assert_eq!(summary["status"], "in_progress");
        assert_eq!(summary["priority"], "high");
    }

    #[test]
    fn unknown_resource_is_rejected() {
        let error = parse_uuid("not-a-uuid", "project_id").expect_err("invalid UUID must fail");
        assert_eq!(error.code, -32602);
    }

    #[test]
    fn limit_is_bounded() {
        let args = json!({"limit": 201});
        assert!(limit_arg(&args, "limit", 50, 200).is_err());
        assert_eq!(limit_arg(&json!({}), "limit", 50, 200).unwrap(), 50);
    }

    #[test]
    fn project_summaries_serialize_for_tools() {
        let project = ProjectSummary {
            id: Uuid::new_v4(),
            name: "Project".to_owned(),
            time_zone: "UTC".to_owned(),
            current_revision: 4,
        };
        let value = serde_json::to_value(project).unwrap();
        assert_eq!(value["current_revision"], 4);
    }
}
