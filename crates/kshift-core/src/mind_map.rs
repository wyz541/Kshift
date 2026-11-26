//! Revision-pinned, read-only mind-map projection over project tasks.
//!
//! The first slice does not introduce a separate mind-map entity. It makes the
//! existing task tree and dependency graph inspectable without creating a
//! second source of truth.

use std::collections::HashSet;

use chrono::{DateTime, Utc};
use domain::{ProjectSnapshot, TaskPriority, TaskStatus};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

/// Default number of task nodes returned by a mind-map projection.
pub const DEFAULT_MIND_MAP_NODE_LIMIT: usize = 256;
/// Maximum number of task nodes accepted by a mind-map projection.
pub const MAX_MIND_MAP_NODE_LIMIT: usize = 1_000;

/// Stable meaning of one projected edge.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MindMapEdgeKind {
    /// Parent task points to its child task.
    Parent,
    /// Task points to the task it depends on.
    Dependency,
}

/// One task rendered as a mind-map node.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct MindMapNode {
    /// Task identity.
    pub id: Uuid,
    /// Task title.
    pub title: String,
    /// Current task status.
    pub status: TaskStatus,
    /// Current task priority.
    pub priority: TaskPriority,
    /// Assigned project members.
    pub assignee_ids: Vec<Uuid>,
    /// Parent task when the task is part of a hierarchy.
    pub parent_task_id: Option<Uuid>,
}

/// One relation between two included task nodes.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct MindMapEdge {
    /// Source task identity.
    pub from_task_id: Uuid,
    /// Target task identity.
    pub to_task_id: Uuid,
    /// Relation meaning.
    pub kind: MindMapEdgeKind,
}

/// Read-only mind-map projection bound to one project revision.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct MindMapProjection {
    /// Project identity.
    pub project_id: Uuid,
    /// Project revision used by the source snapshot.
    pub revision: u64,
    /// Snapshot generation timestamp.
    pub generated_at: DateTime<Utc>,
    /// Included task nodes, ordered by task ID.
    pub nodes: Vec<MindMapNode>,
    /// Edges whose both endpoints are included.
    pub edges: Vec<MindMapEdge>,
    /// Total task count before applying the node limit.
    pub total_nodes: usize,
    /// Whether one or more tasks were omitted.
    pub truncated: bool,
}

/// A mind-map projection invariant failed.
#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum MindMapError {
    /// The caller requested an invalid node limit.
    #[error("node limit must be between 1 and {MAX_MIND_MAP_NODE_LIMIT}")]
    InvalidNodeLimit,
    /// A task in the snapshot belongs to another project.
    #[error("task {task_id} belongs to a different project")]
    CrossProjectTask {
        /// Task that violated project isolation.
        task_id: Uuid,
    },
}

/// Project tasks into a deterministic, revision-pinned read-only mind map.
pub fn project_task_mind_map(
    snapshot: &ProjectSnapshot,
    node_limit: usize,
) -> Result<MindMapProjection, MindMapError> {
    if node_limit == 0 || node_limit > MAX_MIND_MAP_NODE_LIMIT {
        return Err(MindMapError::InvalidNodeLimit);
    }
    if let Some(task) = snapshot
        .tasks
        .iter()
        .find(|task| task.project_id != snapshot.project.id)
    {
        return Err(MindMapError::CrossProjectTask { task_id: task.id });
    }

    let mut tasks = snapshot.tasks.iter().collect::<Vec<_>>();
    tasks.sort_by_key(|task| task.id);
    let total_nodes = tasks.len();
    let nodes = tasks
        .iter()
        .take(node_limit)
        .map(|task| MindMapNode {
            id: task.id,
            title: task.title.clone(),
            status: task.status,
            priority: task.priority,
            assignee_ids: task.assignee_ids.clone(),
            parent_task_id: task.parent_task_id,
        })
        .collect::<Vec<_>>();
    let included = nodes.iter().map(|node| node.id).collect::<HashSet<_>>();
    let mut edges = Vec::new();

    for task in &tasks {
        if !included.contains(&task.id) {
            continue;
        }
        if let Some(parent_task_id) = task.parent_task_id {
            if included.contains(&parent_task_id) {
                edges.push(MindMapEdge {
                    from_task_id: parent_task_id,
                    to_task_id: task.id,
                    kind: MindMapEdgeKind::Parent,
                });
            }
        }
        for dependency_task_id in &task.dependency_task_ids {
            if included.contains(dependency_task_id) {
                edges.push(MindMapEdge {
                    from_task_id: task.id,
                    to_task_id: *dependency_task_id,
                    kind: MindMapEdgeKind::Dependency,
                });
            }
        }
    }
    edges.sort_by_key(|edge| (edge.from_task_id, edge.to_task_id, edge.kind));

    Ok(MindMapProjection {
        project_id: snapshot.project.id,
        revision: snapshot.project.current_revision,
        generated_at: snapshot.generated_at,
        nodes,
        edges,
        total_nodes,
        truncated: total_nodes > node_limit,
    })
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};
    use domain::{Project, ProjectMember, ProjectRole, Task, TaskPriority, TaskStatus};

    use super::*;

    fn task(
        project_id: Uuid,
        id: Uuid,
        parent_task_id: Option<Uuid>,
        dependencies: &[Uuid],
    ) -> Task {
        let now = Utc.with_ymd_and_hms(2026, 11, 26, 0, 0, 0).unwrap();
        Task {
            id,
            project_id,
            title: format!("Task {id}"),
            description_markdown: String::new(),
            status: TaskStatus::Todo,
            priority: TaskPriority::Medium,
            assignee_ids: Vec::new(),
            planned_on: now.date_naive(),
            starts_on: None,
            due_on: None,
            tags: Vec::new(),
            parent_task_id,
            dependency_task_ids: dependencies.to_vec(),
            version: 1,
            created_by: Uuid::new_v4(),
            updated_by: Uuid::new_v4(),
            created_at: now,
            updated_at: now,
        }
    }

    fn snapshot(tasks: Vec<Task>) -> ProjectSnapshot {
        let now = Utc.with_ymd_and_hms(2026, 11, 26, 0, 0, 0).unwrap();
        let project_id = tasks
            .first()
            .map(|task| task.project_id)
            .unwrap_or_else(Uuid::new_v4);
        ProjectSnapshot {
            project: Project {
                id: project_id,
                name: "Mind map".to_owned(),
                time_zone: "UTC".to_owned(),
                current_revision: 7,
                created_at: now,
                updated_at: now,
            },
            members: vec![ProjectMember {
                user_id: Uuid::new_v4(),
                display_name: "Member".to_owned(),
                role: ProjectRole::Editor,
            }],
            tasks,
            audit: Vec::new(),
            generated_at: now,
        }
    }

    #[test]
    fn projects_parent_and_dependency_edges() {
        let project_id = Uuid::new_v4();
        let parent = Uuid::new_v4();
        let child = Uuid::new_v4();
        let dependency = Uuid::new_v4();
        let snapshot = snapshot(vec![
            task(project_id, child, Some(parent), &[dependency]),
            task(project_id, parent, None, &[]),
            task(project_id, dependency, None, &[]),
        ]);

        let projection = project_task_mind_map(&snapshot, 10).expect("projection should succeed");

        assert_eq!(projection.project_id, project_id);
        assert_eq!(projection.revision, 7);
        assert_eq!(projection.total_nodes, 3);
        assert!(!projection.truncated);
        assert!(projection.edges.contains(&MindMapEdge {
            from_task_id: parent,
            to_task_id: child,
            kind: MindMapEdgeKind::Parent,
        }));
        assert!(projection.edges.contains(&MindMapEdge {
            from_task_id: child,
            to_task_id: dependency,
            kind: MindMapEdgeKind::Dependency,
        }));
    }

    #[test]
    fn node_limit_is_stable_and_marks_truncation() {
        let project_id = Uuid::new_v4();
        let snapshot = snapshot(vec![
            task(project_id, Uuid::new_v4(), None, &[]),
            task(project_id, Uuid::new_v4(), None, &[]),
        ]);

        let projection = project_task_mind_map(&snapshot, 1).expect("projection should succeed");

        assert_eq!(projection.nodes.len(), 1);
        assert_eq!(projection.total_nodes, 2);
        assert!(projection.truncated);
        assert!(projection.edges.is_empty());
    }

    #[test]
    fn rejects_cross_project_task_data() {
        let project_id = Uuid::new_v4();
        let mut snapshot = snapshot(vec![task(project_id, Uuid::new_v4(), None, &[])]);
        snapshot
            .tasks
            .push(task(Uuid::new_v4(), Uuid::new_v4(), None, &[]));

        let result = project_task_mind_map(&snapshot, 10);

        assert!(matches!(result, Err(MindMapError::CrossProjectTask { .. })));
    }

    #[test]
    fn empty_project_returns_empty_graph() {
        let snapshot = snapshot(Vec::new());
        let projection = project_task_mind_map(&snapshot, 10).expect("projection should succeed");

        assert!(projection.nodes.is_empty());
        assert!(projection.edges.is_empty());
        assert_eq!(projection.total_nodes, 0);
        assert!(!projection.truncated);
    }
}
