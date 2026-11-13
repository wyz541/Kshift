use std::collections::VecDeque;
use std::sync::{Mutex, MutexGuard};

use domain::{Change, ChangeEvent, ProjectSnapshot, Task};

use crate::ClientError;

const DEFAULT_MAX_PROJECTS: usize = 3;
const DEFAULT_MAX_CACHE_BYTES: usize = 128 * 1024 * 1024;
const DEFAULT_ATTACHMENT_BYTES: usize = 256 * 1024 * 1024;

/// Snapshot cache counters.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CacheStats {
    /// Number of cached projects.
    pub projects: usize,
    /// Estimated normalized snapshot bytes.
    pub bytes: usize,
}

/// Result of applying one incremental event.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EventApplyResult {
    /// Event advanced the cached revision.
    Applied {
        /// New cached revision.
        revision: u64,
    },
    /// Event was already represented by the cache.
    AlreadyApplied,
    /// Event revision was not consecutive.
    Gap {
        /// Revision currently cached.
        current_revision: u64,
        /// Non-consecutive event revision.
        event_revision: u64,
    },
    /// The project is not cached.
    NotCached,
    /// The event was invalid and the cache entry was cleared.
    Invalid,
    /// Applying the event exceeded the snapshot budget.
    BudgetExceeded,
}

struct CacheEntry {
    snapshot: ProjectSnapshot,
    size: usize,
    tick: u64,
}

struct CacheState {
    entries: Vec<CacheEntry>,
    bytes: usize,
    clock: u64,
    max_projects: usize,
    max_bytes: usize,
}

/// Bounded normalized snapshot cache.
pub struct SnapshotCache {
    state: Mutex<CacheState>,
}

impl SnapshotCache {
    /// Create a cache with explicit project and byte limits.
    pub fn new(max_projects: usize, max_bytes: usize) -> Self {
        Self {
            state: Mutex::new(CacheState {
                entries: Vec::new(),
                bytes: 0,
                clock: 1,
                max_projects: max_projects.max(1),
                max_bytes: max_bytes.max(1),
            }),
        }
    }

    /// Insert or replace a snapshot and return whether it fits the budget.
    pub fn put(&self, snapshot: ProjectSnapshot) -> bool {
        let size = estimate_snapshot_bytes(&snapshot);
        let project_id = snapshot.project.id;
        let mut state = self.lock();
        if size > state.max_bytes {
            return false;
        }
        state.remove(project_id);
        while state.entries.len() >= state.max_projects {
            state.evict_oldest(None);
        }
        state.bytes = state.bytes.saturating_add(size);
        let tick = state.next_tick();
        state.entries.push(CacheEntry {
            snapshot,
            size,
            tick,
        });
        while state.bytes > state.max_bytes {
            state.evict_oldest(Some(project_id));
        }
        state
            .entries
            .iter()
            .any(|entry| entry.snapshot.project.id == project_id)
    }

    /// Clone a cached snapshot and mark it most recently used.
    pub fn get(&self, project_id: uuid::Uuid) -> Option<ProjectSnapshot> {
        let mut state = self.lock();
        let tick = state.next_tick();
        let entry = state
            .entries
            .iter_mut()
            .find(|entry| entry.snapshot.project.id == project_id)?;
        entry.tick = tick;
        Some(entry.snapshot.clone())
    }

    /// Return cache counters.
    pub fn stats(&self) -> CacheStats {
        let state = self.lock();
        CacheStats {
            projects: state.entries.len(),
            bytes: state.bytes,
        }
    }

    /// Clear one project.
    pub fn clear_project(&self, project_id: uuid::Uuid) {
        self.lock().remove(project_id);
    }

    /// Clear every project.
    pub fn clear_all(&self) {
        let mut state = self.lock();
        state.entries.clear();
        state.bytes = 0;
    }

    /// Apply a consecutive event to the cached project.
    pub fn apply_event(&self, event: &ChangeEvent) -> EventApplyResult {
        let mut state = self.lock();
        let Some(position) = state
            .entries
            .iter()
            .position(|entry| entry.snapshot.project.id == event.project_id)
        else {
            return EventApplyResult::NotCached;
        };
        let current_revision = state.entries[position].snapshot.project.current_revision;
        if event.revision <= current_revision {
            return EventApplyResult::AlreadyApplied;
        }
        if event.revision != current_revision.saturating_add(1) {
            state.remove_at(position);
            return EventApplyResult::Gap {
                current_revision,
                event_revision: event.revision,
            };
        }
        if event.schema_version != domain::SCHEMA_VERSION {
            state.remove_at(position);
            return EventApplyResult::Invalid;
        }

        let mut snapshot = state.entries[position].snapshot.clone();
        apply_change(&mut snapshot, event);
        snapshot.project.current_revision = event.revision;
        snapshot.generated_at = event.occurred_at;
        let size = estimate_snapshot_bytes(&snapshot);
        if size > state.max_bytes {
            state.remove_at(position);
            return EventApplyResult::BudgetExceeded;
        }

        state.bytes = state.bytes.saturating_sub(state.entries[position].size);
        state.entries[position].snapshot = snapshot;
        state.entries[position].size = size;
        state.bytes = state.bytes.saturating_add(size);
        let project_id = state.entries[position].snapshot.project.id;
        state.entries[position].tick = state.next_tick();
        while state.bytes > state.max_bytes {
            state.evict_oldest(Some(project_id));
        }
        if !state
            .entries
            .iter()
            .any(|entry| entry.snapshot.project.id == project_id)
        {
            return EventApplyResult::BudgetExceeded;
        }
        EventApplyResult::Applied {
            revision: event.revision,
        }
    }

    /// Upsert a project member from `ExecuteCommand`.
    pub fn apply_member(&self, project_id: uuid::Uuid, member: domain::ProjectMember) {
        let mut state = self.lock();
        let Some(position) = state
            .entries
            .iter()
            .position(|entry| entry.snapshot.project.id == project_id)
        else {
            return;
        };
        {
            let entry = &mut state.entries[position];
            if let Some(existing) = entry
                .snapshot
                .members
                .iter_mut()
                .find(|existing| existing.user_id == member.user_id)
            {
                *existing = member;
            } else {
                entry.snapshot.members.push(member);
            }
        }
        state.refresh_entry(position);
    }

    /// Remove a task from the cached project.
    pub fn remove_task(&self, project_id: uuid::Uuid, task_id: uuid::Uuid) {
        let mut state = self.lock();
        let Some(position) = state
            .entries
            .iter()
            .position(|entry| entry.snapshot.project.id == project_id)
        else {
            return;
        };
        state.entries[position]
            .snapshot
            .tasks
            .retain(|task| task.id != task_id);
        state.refresh_entry(position);
    }

    /// Apply a task result from `ExecuteCommand` to the cached snapshot.
    pub fn apply_task(&self, project_id: uuid::Uuid, task: Task) {
        let mut state = self.lock();
        let Some(position) = state
            .entries
            .iter()
            .position(|entry| entry.snapshot.project.id == project_id)
        else {
            return;
        };
        {
            let entry = &mut state.entries[position];
            if let Some(existing) = entry
                .snapshot
                .tasks
                .iter_mut()
                .find(|item| item.id == task.id)
            {
                *existing = task;
            } else {
                entry.snapshot.tasks.push(task);
            }
        }
        state.refresh_entry(position);
    }

    fn lock(&self) -> MutexGuard<'_, CacheState> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

impl Default for SnapshotCache {
    fn default() -> Self {
        Self::new(DEFAULT_MAX_PROJECTS, DEFAULT_MAX_CACHE_BYTES)
    }
}

impl CacheState {
    fn next_tick(&mut self) -> u64 {
        let tick = self.clock;
        self.clock = self.clock.saturating_add(1);
        tick
    }

    fn refresh_entry(&mut self, position: usize) {
        let next_size = estimate_snapshot_bytes(&self.entries[position].snapshot);
        self.bytes = self.bytes.saturating_sub(self.entries[position].size);
        self.entries[position].size = next_size;
        self.bytes = self.bytes.saturating_add(next_size);
        let tick = self.next_tick();
        self.entries[position].tick = tick;
    }

    fn remove(&mut self, project_id: uuid::Uuid) {
        if let Some(position) = self
            .entries
            .iter()
            .position(|entry| entry.snapshot.project.id == project_id)
        {
            self.remove_at(position);
        }
    }

    fn remove_at(&mut self, position: usize) {
        let entry = self.entries.remove(position);
        self.bytes = self.bytes.saturating_sub(entry.size);
    }

    fn evict_oldest(&mut self, protected_project: Option<uuid::Uuid>) {
        let Some((position, _)) = self
            .entries
            .iter()
            .enumerate()
            .filter(|(_, entry)| protected_project != Some(entry.snapshot.project.id))
            .min_by_key(|(_, entry)| entry.tick)
        else {
            return;
        };
        self.remove_at(position);
    }
}

/// In-memory attachment budget and LRU boundary.
pub struct AttachmentCache {
    state: Mutex<AttachmentState>,
}

struct AttachmentState {
    entries: VecDeque<(String, Vec<u8>)>,
    bytes: usize,
    max_bytes: usize,
}

impl AttachmentCache {
    /// Create an attachment cache with a byte budget.
    pub fn new(max_bytes: usize) -> Self {
        Self {
            state: Mutex::new(AttachmentState {
                entries: VecDeque::new(),
                bytes: 0,
                max_bytes: max_bytes.max(1),
            }),
        }
    }

    /// Insert attachment bytes keyed by lowercase SHA-256 hex.
    pub fn put(&self, sha256_hex: &str, bytes: Vec<u8>) -> Result<(), ClientError> {
        validate_sha256_hex(sha256_hex)?;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if bytes.len() > state.max_bytes {
            return Err(ClientError::ResourceExhausted(
                "attachment exceeds the attachment cache budget".to_owned(),
            ));
        }
        state.remove(sha256_hex);
        state.bytes = state.bytes.saturating_add(bytes.len());
        state.entries.push_front((sha256_hex.to_owned(), bytes));
        while state.bytes > state.max_bytes {
            state.evict_oldest();
        }
        Ok(())
    }

    /// Read attachment bytes and mark the entry most recently used.
    pub fn get(&self, sha256_hex: &str) -> Option<Vec<u8>> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let position = state
            .entries
            .iter()
            .position(|(key, _)| key == sha256_hex)?;
        let (key, bytes) = state.entries.remove(position)?;
        let result = bytes.clone();
        state.entries.push_front((key, bytes));
        Some(result)
    }

    /// Remove all cached attachments.
    pub fn clear(&self) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        state.entries.clear();
        state.bytes = 0;
    }
}

impl Default for AttachmentCache {
    fn default() -> Self {
        Self::new(DEFAULT_ATTACHMENT_BYTES)
    }
}

impl AttachmentState {
    fn remove(&mut self, key: &str) {
        if let Some(position) = self.entries.iter().position(|(stored, _)| stored == key) {
            if let Some((_, bytes)) = self.entries.remove(position) {
                self.bytes = self.bytes.saturating_sub(bytes.len());
            }
        }
    }

    fn evict_oldest(&mut self) {
        if let Some((_, bytes)) = self.entries.pop_back() {
            self.bytes = self.bytes.saturating_sub(bytes.len());
        }
    }
}

fn apply_change(snapshot: &mut ProjectSnapshot, event: &ChangeEvent) {
    for change in &event.changes {
        match change {
            Change::ProjectUpserted { project } => snapshot.project = project.clone(),
            Change::ProjectMemberUpserted { member } => {
                if let Some(existing) = snapshot
                    .members
                    .iter_mut()
                    .find(|existing| existing.user_id == member.user_id)
                {
                    *existing = member.clone();
                } else {
                    snapshot.members.push(member.clone());
                }
            }
            Change::TaskCreated { task } | Change::TaskUpdated { task } => {
                if let Some(existing) = snapshot.tasks.iter_mut().find(|item| item.id == task.id) {
                    *existing = task.clone();
                } else {
                    snapshot.tasks.push(task.clone());
                }
            }
            Change::TaskDeleted { task_id } => {
                snapshot.tasks.retain(|task| task.id != *task_id);
            }
        }
    }
}

fn estimate_snapshot_bytes(snapshot: &ProjectSnapshot) -> usize {
    serde_json::to_vec(snapshot)
        .map(|bytes| bytes.len())
        .unwrap_or(usize::MAX)
}

fn validate_sha256_hex(value: &str) -> Result<(), ClientError> {
    if value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        Ok(())
    } else {
        Err(ClientError::InvalidArgument(
            "attachment key must be a 64-character SHA-256 hex string".to_owned(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{NaiveDate, Utc};
    use domain::{
        Change, ChangeEvent, Project, ProjectMember, ProjectRole, TaskPriority, TaskStatus,
    };
    use uuid::Uuid;

    fn snapshot(project_id: Uuid) -> ProjectSnapshot {
        let now = Utc::now();
        ProjectSnapshot {
            project: Project {
                id: project_id,
                name: "Project".to_owned(),
                time_zone: "Asia/Shanghai".to_owned(),
                current_revision: 1,
                created_at: now,
                updated_at: now,
            },
            members: Vec::new(),
            tasks: Vec::new(),
            generated_at: now,
        }
    }

    fn task(project_id: Uuid) -> Task {
        let now = Utc::now();
        Task {
            id: Uuid::new_v4(),
            project_id,
            title: "Task".to_owned(),
            description_markdown: String::new(),
            status: TaskStatus::Todo,
            priority: TaskPriority::Medium,
            assignee_ids: Vec::new(),
            planned_on: NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
            starts_on: None,
            due_on: Some(NaiveDate::from_ymd_opt(2026, 11, 20).unwrap()),
            tags: Vec::new(),
            parent_task_id: None,
            dependency_task_ids: Vec::new(),
            version: 1,
            created_by: Uuid::new_v4(),
            updated_by: Uuid::new_v4(),
            created_at: now,
            updated_at: now,
        }
    }

    fn event(project_id: Uuid, revision: u64) -> ChangeEvent {
        ChangeEvent {
            project_id,
            revision,
            schema_version: domain::SCHEMA_VERSION,
            command_id: Uuid::new_v4(),
            occurred_at: Utc::now(),
            changes: vec![Change::TaskCreated {
                task: task(project_id),
            }],
        }
    }

    #[test]
    fn applies_consecutive_event_and_rejects_gap() {
        let cache = SnapshotCache::new(3, 1024 * 1024);
        let project_id = Uuid::new_v4();
        assert!(cache.put(snapshot(project_id)));
        assert_eq!(
            cache.apply_event(&event(project_id, 2)),
            EventApplyResult::Applied { revision: 2 }
        );
        assert!(matches!(
            cache.apply_event(&event(project_id, 4)),
            EventApplyResult::Gap { .. }
        ));
        assert!(cache.get(project_id).is_none());
    }

    #[test]
    fn evicts_least_recent_project() {
        let cache = SnapshotCache::new(2, 1024 * 1024);
        let first = Uuid::new_v4();
        let second = Uuid::new_v4();
        let third = Uuid::new_v4();
        assert!(cache.put(snapshot(first)));
        assert!(cache.put(snapshot(second)));
        assert!(cache.get(first).is_some());
        assert!(cache.put(snapshot(third)));
        assert!(cache.get(first).is_some());
        assert!(cache.get(third).is_some());
        assert!(cache.get(second).is_none());
    }

    #[test]
    fn upserts_member_on_event() {
        let cache = SnapshotCache::new(3, 1024 * 1024);
        let project_id = Uuid::new_v4();
        assert!(cache.put(snapshot(project_id)));
        let member = ProjectMember {
            user_id: Uuid::new_v4(),
            display_name: "Member".to_owned(),
            role: ProjectRole::Editor,
        };
        let event = ChangeEvent {
            project_id,
            revision: 2,
            schema_version: domain::SCHEMA_VERSION,
            command_id: Uuid::new_v4(),
            occurred_at: Utc::now(),
            changes: vec![Change::ProjectMemberUpserted { member }],
        };
        assert!(matches!(
            cache.apply_event(&event),
            EventApplyResult::Applied { .. }
        ));
        assert_eq!(cache.get(project_id).unwrap().members.len(), 1);
    }
}
