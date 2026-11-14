//! Authoritative Kshift domain and in-memory transport for the R2 MVP.

mod model;
mod plan_depth;
mod store;

pub use model::{
    CommandEnvelope, CommandError, CommandResponse, CreateTaskCommand, MoveTaskCommand, Person,
    ProjectAuditEntry, ProjectSnapshot, ProjectSummary, SetTasksStatusCommand, TaskCommand,
    TaskHistoryEntry, TaskItem, TaskPriority, TaskStatus, TaskVersionRef, UpdateTaskCommand,
};
pub use plan_depth::{
    AttachmentLink, AttachmentMetadata, AttachmentPolicy, PLAN_SCHEMA_VERSION, PlanActorRole,
    PlanCommand, PlanCommandEnvelope, PlanCommandResponse, PlanDepthSnapshot, PlanDepthStore,
    PlanError, PlanHistoryEntry, PlanProject, PlanStatistics, PlanTask, PlanTaskDraft, ReportRange,
    ReportTask, TaskDependency, WorkReport, build_report_html, demo_snapshot,
};
pub use store::{KshiftStore, StoreError};
