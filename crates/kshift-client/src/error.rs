use contract::v1::{ErrorCode, ErrorDetail};
use domain::DomainError;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

const MAX_SAFE_MESSAGE_CHARS: usize = 512;

/// Server-provided conflict details.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ConflictDetails {
    /// Current project revision.
    pub current_revision: Option<u64>,
    /// Conflicting entity identity.
    pub entity_id: Option<Uuid>,
    /// Current entity version.
    pub current_entity_version: Option<u64>,
}

/// Typed client failure.
#[derive(Debug, thiserror::Error)]
pub enum ClientError {
    /// Configuration is invalid.
    #[error("invalid configuration: {0}")]
    InvalidConfig(String),
    /// A caller input is invalid.
    #[error("invalid argument: {0}")]
    InvalidArgument(String),
    /// A valid token is required.
    #[error("authentication token is not configured")]
    AuthenticationRequired,
    /// The server rejected authentication.
    #[error("authentication failed")]
    Unauthenticated,
    /// The server denied project authorization.
    #[error("permission denied")]
    PermissionDenied,
    /// The requested entity does not exist.
    #[error("not found: {0}")]
    NotFound(String),
    /// The server rejected an outdated precondition.
    #[error("write conflict")]
    Conflict(ConflictDetails),
    /// A revision gap requires a fresh snapshot.
    #[error("snapshot reset required at revision {current_revision}")]
    ResetRequired {
        /// Revision currently known by the client.
        current_revision: u64,
        /// Oldest revision retained by the server.
        minimum_retained_revision: u64,
        /// Server reset reason.
        reason: domain::ResetReason,
    },
    /// A unique entity already exists.
    #[error("already exists: {0}")]
    AlreadyExists(String),
    /// The server or client resource budget was exhausted.
    #[error("resource exhausted: {0}")]
    ResourceExhausted(String),
    /// The server rejected a failed precondition.
    #[error("failed precondition: {0}")]
    FailedPrecondition(String),
    /// The transport is temporarily unavailable.
    #[error("service unavailable: {0}")]
    Unavailable(String),
    /// The RPC deadline elapsed.
    #[error("deadline exceeded")]
    DeadlineExceeded,
    /// The operation was cancelled.
    #[error("operation cancelled")]
    Cancelled,
    /// The server returned a malformed or unsupported payload.
    #[error("protocol error: {0}")]
    Protocol(String),
    /// The response exceeded a configured byte limit.
    #[error("{field} is {actual} bytes; limit is {limit} bytes")]
    ResponseTooLarge {
        /// Response field name.
        field: &'static str,
        /// Actual size.
        actual: usize,
        /// Configured limit.
        limit: usize,
    },
    /// No matching project is present in the memory cache.
    #[error("cached snapshot not found for project {0}")]
    CacheMiss(String),
    /// A domain invariant failed.
    #[error(transparent)]
    Domain(#[from] DomainError),
    /// An unexpected internal failure occurred.
    #[error("internal client error: {0}")]
    Internal(String),
}

/// UI-safe client error projection.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ClientErrorView {
    /// Stable error code.
    pub code: String,
    /// Bounded, user-safe message.
    pub message: String,
    /// Whether retrying may succeed.
    pub retryable: bool,
    /// Current server revision when supplied.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current_revision: Option<u64>,
    /// Conflicting entity when supplied.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entity_id: Option<String>,
    /// Conflicting entity version when supplied.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entity_version: Option<u64>,
}

impl ClientError {
    /// Stable machine-readable error code.
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidConfig(_) | Self::InvalidArgument(_) | Self::Domain(_) => {
                "invalid_argument"
            }
            Self::AuthenticationRequired | Self::Unauthenticated => "unauthenticated",
            Self::PermissionDenied => "permission_denied",
            Self::NotFound(_) => "not_found",
            Self::Conflict(_) => "conflict",
            Self::ResetRequired { .. } => "reset_required",
            Self::AlreadyExists(_) => "already_exists",
            Self::ResourceExhausted(_) => "resource_exhausted",
            Self::FailedPrecondition(_) => "failed_precondition",
            Self::Unavailable(_) => "unavailable",
            Self::DeadlineExceeded => "deadline_exceeded",
            Self::Cancelled => "cancelled",
            Self::Protocol(_) | Self::ResponseTooLarge { .. } => "protocol_error",
            Self::CacheMiss(_) => "cache_miss",
            Self::Internal(_) => "internal",
        }
    }

    /// Whether an idempotent operation may be retried.
    pub fn retryable(&self) -> bool {
        matches!(self, Self::ResourceExhausted(_) | Self::Unavailable(_))
    }

    /// Project-safe error representation for a Swift host.
    pub fn view(&self) -> ClientErrorView {
        let (current_revision, entity_id, entity_version) = match self {
            Self::Conflict(details) => (
                details.current_revision,
                details.entity_id.map(|value| value.to_string()),
                details.current_entity_version,
            ),
            Self::ResetRequired {
                current_revision, ..
            } => (Some(*current_revision), None, None),
            _ => (None, None, None),
        };
        ClientErrorView {
            code: self.code().to_owned(),
            message: sanitize_message(&self.to_string()),
            retryable: self.retryable(),
            current_revision,
            entity_id,
            entity_version,
        }
    }

    /// Map a tonic status and bounded `ErrorDetail` into a typed error.
    pub(crate) fn from_status(status: tonic::Status) -> Self {
        if let Ok(detail) = contract::error_detail(&status) {
            if let Ok(code) = ErrorCode::try_from(detail.code) {
                return Self::from_detail(status, detail, code);
            }
        }
        Self::from_grpc_code(status)
    }

    fn from_detail(status: tonic::Status, detail: ErrorDetail, code: ErrorCode) -> Self {
        let message = sanitize_message(if detail.message.is_empty() {
            status.message()
        } else {
            &detail.message
        });
        let conflict_details = || ConflictDetails {
            current_revision: detail.current_project_revision,
            entity_id: non_empty(&detail.entity_id).and_then(|value| Uuid::parse_str(&value).ok()),
            current_entity_version: detail.current_entity_version,
        };
        match code {
            ErrorCode::AuthRequired => Self::Unauthenticated,
            ErrorCode::Forbidden => Self::PermissionDenied,
            ErrorCode::InvalidInput => Self::InvalidArgument(message),
            ErrorCode::InvalidState => Self::FailedPrecondition(message),
            ErrorCode::Conflict => Self::Conflict(conflict_details()),
            ErrorCode::ResetRequired => Self::ResetRequired {
                current_revision: detail.current_project_revision.unwrap_or(0),
                minimum_retained_revision: detail.minimum_retained_revision.unwrap_or(0),
                reason: domain::ResetReason::RetentionGap,
            },
            ErrorCode::SchemaMismatch => Self::ResetRequired {
                current_revision: detail.current_project_revision.unwrap_or(0),
                minimum_retained_revision: detail.minimum_retained_revision.unwrap_or(0),
                reason: domain::ResetReason::SchemaMismatch,
            },
            ErrorCode::AlreadyExists => Self::AlreadyExists(message),
            ErrorCode::LimitExceeded => Self::ResourceExhausted(message),
            ErrorCode::FailedPrecondition => Self::FailedPrecondition(message),
            ErrorCode::Internal | ErrorCode::Unspecified => Self::from_grpc_code(status),
        }
    }

    fn from_grpc_code(status: tonic::Status) -> Self {
        let message = sanitize_message(status.message());
        match status.code() {
            tonic::Code::InvalidArgument | tonic::Code::OutOfRange => {
                Self::InvalidArgument(message)
            }
            tonic::Code::Unauthenticated => Self::Unauthenticated,
            tonic::Code::PermissionDenied => Self::PermissionDenied,
            tonic::Code::NotFound => Self::NotFound(message),
            tonic::Code::Aborted => Self::Conflict(ConflictDetails {
                current_revision: None,
                entity_id: None,
                current_entity_version: None,
            }),
            tonic::Code::AlreadyExists => Self::AlreadyExists(message),
            tonic::Code::FailedPrecondition => Self::FailedPrecondition(message),
            tonic::Code::ResourceExhausted => Self::ResourceExhausted(message),
            tonic::Code::Unavailable => Self::Unavailable(message),
            tonic::Code::DeadlineExceeded => Self::DeadlineExceeded,
            tonic::Code::Cancelled => Self::Cancelled,
            tonic::Code::Unimplemented | tonic::Code::DataLoss | tonic::Code::Internal => {
                Self::Internal(message)
            }
            tonic::Code::Ok | tonic::Code::Unknown => Self::Protocol(message),
        }
    }
}

impl From<tonic::Status> for ClientError {
    fn from(value: tonic::Status) -> Self {
        Self::from_status(value)
    }
}

fn sanitize_message(value: &str) -> String {
    let mut output = String::with_capacity(value.len().min(MAX_SAFE_MESSAGE_CHARS * 4));
    for character in value.chars().take(MAX_SAFE_MESSAGE_CHARS) {
        if character.is_control() {
            output.push(' ');
        } else {
            output.push(character);
        }
    }
    output.trim().to_owned()
}

fn non_empty(value: &str) -> Option<String> {
    (!value.is_empty()).then(|| value.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use prost::Message;

    #[test]
    fn conflict_detail_is_preserved() {
        let entity_id = Uuid::new_v4();
        let detail = ErrorDetail {
            code: ErrorCode::Conflict as i32,
            message: "stale task".to_owned(),
            request_id: "request-1".to_owned(),
            project_id: Uuid::new_v4().to_string(),
            entity_id: entity_id.to_string(),
            current_project_revision: Some(9),
            current_entity_version: Some(4),
            minimum_retained_revision: None,
        };
        let status = tonic::Status::with_details(
            tonic::Code::Aborted,
            "conflict",
            detail.encode_to_vec().into(),
        );
        let error = ClientError::from_status(status);
        assert!(matches!(error, ClientError::Conflict(_)));
        let view = error.view();
        assert_eq!(view.current_revision, Some(9));
        assert_eq!(view.entity_id, Some(entity_id.to_string()));
    }

    #[test]
    fn error_view_is_bounded_and_control_free() {
        let error = ClientError::InvalidArgument(format!("{}\n", "x".repeat(10_000)));
        let view = error.view();
        assert!(view.message.chars().count() <= MAX_SAFE_MESSAGE_CHARS);
        assert!(!view.message.contains('\n'));
    }
}
