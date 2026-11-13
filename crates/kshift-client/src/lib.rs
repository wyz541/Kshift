use kshift_core::{
    CommandEnvelope, CommandError, CommandResponse, KshiftStore, ProjectSnapshot, ProjectSummary,
    StoreError,
};
use serde::Serialize;

#[derive(Debug, Serialize)]
struct ProjectsResponse {
    ok: bool,
    projects: Vec<ProjectSummary>,
    error: Option<ApiError>,
}

#[derive(Debug, Serialize)]
struct SnapshotResponse {
    ok: bool,
    snapshot: Option<ProjectSnapshot>,
    error: Option<ApiError>,
}

#[derive(Debug, Serialize)]
struct ApiError {
    code: String,
    message: String,
}

#[derive(Debug)]
pub struct KshiftClient {
    store: KshiftStore,
}

impl Default for KshiftClient {
    fn default() -> Self {
        Self::new()
    }
}

impl KshiftClient {
    pub fn new() -> Self {
        Self {
            store: KshiftStore::new(),
        }
    }

    pub fn projects_json(&self) -> String {
        let response = ProjectsResponse {
            ok: true,
            projects: self.store.project_summaries(),
            error: None,
        };
        serde_json::to_string(&response).unwrap_or_else(|_| internal_error_json())
    }

    pub fn snapshot_json(&self, project_id: &str) -> String {
        let response = match self.store.snapshot(project_id) {
            Ok(snapshot) => SnapshotResponse {
                ok: true,
                snapshot: Some(snapshot),
                error: None,
            },
            Err(error) => SnapshotResponse {
                ok: false,
                snapshot: None,
                error: Some(map_store_error(error)),
            },
        };
        serde_json::to_string(&response).unwrap_or_else(|_| internal_error_json())
    }

    pub fn execute_json(&mut self, project_id: &str, request_json: &str) -> String {
        let envelope: CommandEnvelope = match serde_json::from_str(request_json) {
            Ok(envelope) => envelope,
            Err(error) => {
                let response = CommandResponse::failure(
                    "unknown".into(),
                    CommandError {
                        code: "invalid_json".into(),
                        message: format!("命令 JSON 无效：{error}"),
                        current_revision: None,
                        current_task_version: None,
                        task_id: None,
                    },
                );
                return serde_json::to_string(&response).unwrap_or_else(|_| internal_error_json());
            }
        };

        let response = self.store.execute(project_id, &envelope);
        serde_json::to_string(&response).unwrap_or_else(|_| internal_error_json())
    }
}

fn map_store_error(error: StoreError) -> ApiError {
    match error {
        StoreError::ProjectNotFound(project_id) => ApiError {
            code: "project_not_found".into(),
            message: format!("项目不存在：{project_id}"),
        },
    }
}

fn internal_error_json() -> String {
    r#"{"ok":false,"error":{"code":"serialization_error","message":"客户端返回序列化失败。"}}"#
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn projects_and_snapshot_are_json_safe() {
        let client = KshiftClient::new();
        let projects = client.projects_json();
        assert!(projects.contains("project-focus-2026"));
        assert!(!projects.contains("protobuf"));
        let snapshot = client.snapshot_json("project-customer");
        assert!(snapshot.contains("task-customer-call"));
        assert!(!snapshot.contains("task-ui-review"));
    }

    #[test]
    fn invalid_json_returns_typed_error() {
        let mut client = KshiftClient::new();
        let response = client.execute_json("project-focus-2026", "{");
        assert!(response.contains("invalid_json"));
    }
}
