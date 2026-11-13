//! Authoritative Kshift domain and in-memory transport for the R2 MVP.

mod model;
mod store;

pub use model::{
    CommandEnvelope, CommandError, CommandResponse, CreateTaskCommand, MoveTaskCommand, Person,
    ProjectAuditEntry, ProjectSnapshot, ProjectSummary, SetTasksStatusCommand, TaskCommand,
    TaskHistoryEntry, TaskItem, TaskPriority, TaskStatus, TaskVersionRef, UpdateTaskCommand,
};
pub use store::{KshiftStore, StoreError};
