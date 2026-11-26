//! Backend boundary used by the MCP protocol adapter.

use std::{env, fs, time::Duration};

use async_trait::async_trait;
use domain::ProjectSnapshot;
use kshift_client::{
    AuthToken, ClientConfig, ClientError, KshiftClient, ProjectSummary, DEFAULT_DEADLINE,
    MAX_RESPONSE_BYTES,
};
use thiserror::Error;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

/// Stable, bounded error taxonomy exposed to MCP tool callers.
#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum McpError {
    /// Tool input is malformed or out of range.
    #[error("{0}")]
    InvalidArgument(String),
    /// Authentication is required or rejected.
    #[error("authentication is required")]
    Unauthenticated,
    /// The caller cannot access the requested project.
    #[error("permission denied")]
    PermissionDenied,
    /// The requested entity does not exist.
    #[error("{0}")]
    NotFound(String),
    /// The operation is not available in read-only mode.
    #[error("{0}")]
    ReadOnly(String),
    /// The shared client is temporarily unavailable.
    #[error("{0}")]
    Unavailable(String),
    /// The request was cancelled.
    #[error("request cancelled")]
    Cancelled,
    /// An unexpected adapter failure occurred.
    #[error("internal MCP adapter error")]
    Internal,
}

impl McpError {
    /// Stable machine-readable error code.
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidArgument(_) => "invalid_argument",
            Self::Unauthenticated => "unauthenticated",
            Self::PermissionDenied => "permission_denied",
            Self::NotFound(_) => "not_found",
            Self::ReadOnly(_) => "read_only",
            Self::Unavailable(_) => "unavailable",
            Self::Cancelled => "cancelled",
            Self::Internal => "internal",
        }
    }

    /// Whether a read-only client may retry the request.
    pub fn retryable(&self) -> bool {
        matches!(self, Self::Unavailable(_))
    }
}

impl From<ClientError> for McpError {
    fn from(value: ClientError) -> Self {
        match value {
            ClientError::InvalidConfig(message) | ClientError::InvalidArgument(message) => {
                Self::InvalidArgument(message)
            }
            ClientError::AuthenticationRequired | ClientError::Unauthenticated => {
                Self::Unauthenticated
            }
            ClientError::PermissionDenied => Self::PermissionDenied,
            ClientError::NotFound(message) => Self::NotFound(message),
            ClientError::Unavailable(message) => Self::Unavailable(message),
            ClientError::ResourceExhausted(message) => Self::Unavailable(message),
            ClientError::ResponseTooLarge { .. } => {
                Self::Unavailable("response exceeded MCP output budget".to_owned())
            }
            ClientError::DeadlineExceeded => {
                Self::Unavailable("request deadline exceeded".to_owned())
            }
            ClientError::Cancelled => Self::Cancelled,
            ClientError::Conflict(_)
            | ClientError::ResetRequired { .. }
            | ClientError::AlreadyExists(_)
            | ClientError::FailedPrecondition(_)
            | ClientError::CacheMiss(_)
            | ClientError::Domain(_)
            | ClientError::Protocol(_)
            | ClientError::Internal(_) => Self::Internal,
        }
    }
}

/// Read-only backend contract used by the MCP protocol layer.
#[async_trait]
pub trait McpBackend: Send + Sync {
    /// List projects visible to the authenticated Kshift identity.
    async fn list_projects(&self) -> Result<Vec<ProjectSummary>, McpError>;

    /// Read one authorized project snapshot.
    async fn get_snapshot(&self, project_id: Uuid) -> Result<ProjectSnapshot, McpError>;
}

/// Shared-client backend for the real stdio MCP process.
pub struct KshiftBackend {
    client: KshiftClient,
    cancellation: CancellationToken,
}

impl KshiftBackend {
    /// Build a backend from the standard Kshift MCP environment variables.
    ///
    /// Required: `KSHIFT_ENDPOINT`, `KSHIFT_CA_PATH`, `KSHIFT_TOKEN`.
    /// Optional: `KSHIFT_TLS_DOMAIN`, `KSHIFT_MCP_DEADLINE_SECS`.
    pub async fn from_env() -> anyhow::Result<Self> {
        let endpoint = env::var("KSHIFT_ENDPOINT")
            .map_err(|_| anyhow::anyhow!("KSHIFT_ENDPOINT is required"))?;
        let ca_path = env::var("KSHIFT_CA_PATH")
            .map_err(|_| anyhow::anyhow!("KSHIFT_CA_PATH is required"))?;
        let ca_pem = fs::read(&ca_path)
            .map_err(|error| anyhow::anyhow!("failed to read KSHIFT_CA_PATH: {error}"))?;
        let token =
            env::var("KSHIFT_TOKEN").map_err(|_| anyhow::anyhow!("KSHIFT_TOKEN is required"))?;
        let tls_domain = env::var("KSHIFT_TLS_DOMAIN").ok();
        let deadline = env::var("KSHIFT_MCP_DEADLINE_SECS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .map(Duration::from_secs)
            .unwrap_or(DEFAULT_DEADLINE);
        let config = ClientConfig::new(endpoint, ca_pem, tls_domain, deadline, MAX_RESPONSE_BYTES)?;
        let client = KshiftClient::new(config)?;
        client.set_token(AuthToken::new(token)?).await;
        Ok(Self {
            client,
            cancellation: CancellationToken::new(),
        })
    }

    /// Cancel any in-flight backend request.
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
}

#[async_trait]
impl McpBackend for KshiftBackend {
    async fn list_projects(&self) -> Result<Vec<ProjectSummary>, McpError> {
        self.client
            .list_projects(None, &self.cancellation)
            .await
            .map_err(McpError::from)
    }

    async fn get_snapshot(&self, project_id: Uuid) -> Result<ProjectSnapshot, McpError> {
        self.client
            .get_snapshot(project_id, None, &self.cancellation)
            .await
            .map_err(McpError::from)
    }
}
