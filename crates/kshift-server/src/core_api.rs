//! Shell-neutral Core API boundary for Kshift server use cases.
//!
//! This module deliberately contains no gRPC, protobuf, SQLx, or UI types.
//! The first slice keeps the existing PostgreSQL implementation in the server
//! while making the use-case contract explicit and testable.

use std::future::Future;

use async_trait::async_trait;
use domain::{ChangeEvent, CommandEnvelope, Project, ProjectSnapshot, ResetReason};
use thiserror::Error;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

/// Request metadata supplied by a shell adapter.
#[derive(Clone, Debug)]
pub struct ExecutionContext {
    /// Authenticated actor ID. The server never trusts a shell-provided actor.
    pub actor_id: Uuid,
    /// Server-authoritative administrator flag.
    pub is_admin: bool,
    /// Unique request identifier used for tracing and action audit.
    pub request_id: Uuid,
    /// Optional distributed trace identifier propagated by the adapter.
    pub trace_id: Option<String>,
    /// Absolute deadline enforced by the Core API.
    pub deadline: Option<tokio::time::Instant>,
    /// Cancellation signal owned by the shell adapter.
    pub cancellation: CancellationToken,
}

impl ExecutionContext {
    /// Create a core execution context.
    pub fn new(actor_id: Uuid, is_admin: bool, request_id: Uuid) -> Self {
        Self {
            actor_id,
            is_admin,
            request_id,
            trace_id: None,
            deadline: None,
            cancellation: CancellationToken::new(),
        }
    }

    /// Attach an absolute deadline to this execution context.
    pub fn with_deadline(mut self, deadline: tokio::time::Instant) -> Self {
        self.deadline = Some(deadline);
        self
    }

    /// Attach a cancellation signal to this execution context.
    pub fn with_cancellation(mut self, cancellation: CancellationToken) -> Self {
        self.cancellation = cancellation;
        self
    }
}

/// Run one Core API future with the deadline and cancellation from `context`.
pub async fn run_with_context<F, T>(context: &ExecutionContext, future: F) -> Result<T, CoreError>
where
    F: Future<Output = Result<T, CoreError>>,
{
    if context.cancellation.is_cancelled() {
        return Err(CoreError::Cancelled);
    }
    if let Some(deadline) = context.deadline {
        if tokio::time::Instant::now() >= deadline {
            return Err(CoreError::DeadlineExceeded);
        }
        tokio::select! {
            _ = context.cancellation.cancelled() => Err(CoreError::Cancelled),
            result = tokio::time::timeout_at(deadline, future) => {
                result.map_err(|_| CoreError::DeadlineExceeded)?
            }
        }
    } else {
        tokio::select! {
            _ = context.cancellation.cancelled() => Err(CoreError::Cancelled),
            result = future => result,
        }
    }
}

/// A typed command plus the adapter's canonical request digest.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CoreCommandRequest {
    /// Domain command envelope with actor-independent business input.
    pub envelope: CommandEnvelope,
    /// Digest used to reject mismatched idempotency replays.
    pub request_digest: Vec<u8>,
}

/// Domain-level outcome of one committed command.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CommandOutcome {
    /// Stable command identifier.
    pub command_id: Uuid,
    /// Project revision produced by the command.
    pub project_revision: u64,
    /// Domain event representing the committed change.
    pub event: ChangeEvent,
}

/// Stable, shell-neutral error taxonomy for Core API calls.
#[derive(Debug, Error, Clone, Eq, PartialEq)]
pub enum CoreError {
    /// Input failed validation or has an invalid shape.
    #[error("{0}")]
    InvalidArgument(String),
    /// Authentication is required.
    #[error("authentication is required")]
    Unauthenticated,
    /// The actor cannot perform this operation.
    #[error("permission denied")]
    PermissionDenied,
    /// A requested entity does not exist.
    #[error("{0}")]
    NotFound(String),
    /// Revision or entity-version precondition failed.
    #[error("revision or entity version conflict")]
    Conflict {
        /// Current project revision, when known.
        current_revision: Option<u64>,
        /// Conflicting entity ID, when known.
        entity_id: Option<Uuid>,
        /// Current entity version, when known.
        current_entity_version: Option<u64>,
    },
    /// The caller must fetch a fresh snapshot.
    #[error("client must fetch a new snapshot")]
    ResetRequired {
        /// Current project revision.
        current_revision: u64,
        /// Minimum revision retained by the event stream.
        minimum_retained_revision: u64,
        /// Stable reset reason.
        reason: ResetReason,
    },
    /// The entity or key already exists.
    #[error("{0}")]
    AlreadyExists(String),
    /// The operation is not available under current conditions.
    #[error("{0}")]
    FailedPrecondition(String),
    /// A bounded resource or concurrency limit was reached.
    #[error("{0}")]
    ResourceExhausted(String),
    /// The core is temporarily unavailable.
    #[error("{0}")]
    Unavailable(String),
    /// The operation is unsupported.
    #[error("{0}")]
    Unsupported(String),
    /// A deadline elapsed before completion.
    #[error("request deadline exceeded")]
    DeadlineExceeded,
    /// The caller cancelled the operation.
    #[error("request cancelled")]
    Cancelled,
    /// An unexpected internal failure occurred.
    #[error("internal server error")]
    Internal,
}

impl From<domain::DomainError> for CoreError {
    fn from(value: domain::DomainError) -> Self {
        match value {
            domain::DomainError::Validation(message) => Self::InvalidArgument(message),
            domain::DomainError::NotFound(message) => Self::NotFound(message),
            domain::DomainError::PermissionDenied => Self::PermissionDenied,
            domain::DomainError::Conflict {
                current_revision,
                entity_id,
                current_entity_version,
            } => Self::Conflict {
                current_revision,
                entity_id,
                current_entity_version,
            },
            domain::DomainError::ResetRequired {
                current_revision,
                minimum_retained_revision,
                reason,
            } => Self::ResetRequired {
                current_revision,
                minimum_retained_revision,
                reason,
            },
            domain::DomainError::AlreadyExists(message) => Self::AlreadyExists(message),
            domain::DomainError::Unsupported(message) => Self::Unsupported(message),
        }
    }
}

/// Shell-neutral use cases implemented by the single authoritative Core Runtime.
#[async_trait]
pub trait CoreApi: Send + Sync {
    /// List projects visible to the authenticated actor.
    async fn list_projects(&self, context: &ExecutionContext) -> Result<Vec<Project>, CoreError>;

    /// Read one project snapshot visible to the authenticated actor.
    async fn project_snapshot(
        &self,
        context: &ExecutionContext,
        project_id: Uuid,
    ) -> Result<ProjectSnapshot, CoreError>;

    /// Execute one typed command with the shared transaction and idempotency semantics.
    async fn execute_command(
        &self,
        context: &ExecutionContext,
        request: CoreCommandRequest,
    ) -> Result<CommandOutcome, CoreError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn expired_deadline_is_a_typed_core_error() {
        let context = ExecutionContext::new(Uuid::new_v4(), false, Uuid::new_v4())
            .with_deadline(tokio::time::Instant::now() - std::time::Duration::from_millis(1));
        let result = run_with_context(&context, async { Ok::<_, CoreError>(()) }).await;
        assert_eq!(result, Err(CoreError::DeadlineExceeded));
    }

    #[tokio::test]
    async fn cancelled_context_is_a_typed_core_error() {
        let cancellation = CancellationToken::new();
        cancellation.cancel();
        let context = ExecutionContext::new(Uuid::new_v4(), false, Uuid::new_v4())
            .with_cancellation(cancellation);
        let result = run_with_context(&context, async { Ok::<_, CoreError>(()) }).await;
        assert_eq!(result, Err(CoreError::Cancelled));
    }
}
