//! Safe Rust host API for Rust UI hosts.
//!
//! The C ABI in this crate serves the macOS and iOS hosts. Rust UI hosts,
//! such as the Windows gpui client, call this module instead of raw pointers.
//! Every call returns bounded JSON that matches the C ABI projections.

use std::sync::Arc;
use std::time::Duration;

use kshift_client::{AuthToken, ClientConfig, KshiftClient, DEFAULT_DEADLINE, MAX_RESPONSE_BYTES};
use tokio::runtime::Runtime;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::registry;

/// Maximum size of one host JSON response.
pub const MAX_HOST_JSON_BYTES: usize = MAX_RESPONSE_BYTES;

/// A Kshift client owned by a Rust UI host.
///
/// The handle owns a Tokio runtime. Dropping it cancels subscriptions and
/// stops the runtime workers.
pub struct HostClient {
    runtime: Arc<Runtime>,
    core: Arc<KshiftClient>,
    shutdown: CancellationToken,
}

impl HostClient {
    /// Create a host client.
    ///
    /// The first RPC opens the TLS connection. `deadline` falls back to the
    /// client default when it is `None`.
    pub fn connect(
        endpoint: &str,
        ca_pem: Vec<u8>,
        tls_domain: Option<String>,
        deadline: Option<Duration>,
    ) -> Result<Self, String> {
        let config = ClientConfig::new(
            endpoint.to_owned(),
            ca_pem,
            tls_domain,
            deadline.unwrap_or(DEFAULT_DEADLINE),
            MAX_RESPONSE_BYTES,
        )
        .map_err(|error| error.to_string())?;
        let runtime = registry::new_runtime().map_err(|error| format!("{error:?}"))?;
        let core = runtime
            .block_on(async { KshiftClient::new(config) })
            .map_err(|error| error.to_string())?;
        Ok(Self {
            runtime,
            core: Arc::new(core),
            shutdown: CancellationToken::new(),
        })
    }

    /// Replace the bearer token.
    pub fn set_token(&self, token: &str) -> Result<(), String> {
        let token = AuthToken::new(token.to_owned()).map_err(|error| error.to_string())?;
        self.runtime.block_on(self.core.set_token(token));
        Ok(())
    }

    /// List projects visible to the current identity as JSON.
    pub fn list_projects_json(&self) -> Result<String, String> {
        let cancel = CancellationToken::new();
        let projects = self
            .runtime
            .block_on(self.core.list_projects(None, &cancel))
            .map_err(|error| error.to_string())?;
        bounded_json(&projects)
    }

    /// Fetch one project snapshot and update the memory cache as JSON.
    pub fn snapshot_json(&self, project_id: &str) -> Result<String, String> {
        let project_id = Uuid::parse_str(project_id)
            .map_err(|error| format!("invalid project_id: {error}"))?;
        let cancel = CancellationToken::new();
        let snapshot = self
            .runtime
            .block_on(self.core.get_snapshot(project_id, None, &cancel))
            .map_err(|error| error.to_string())?;
        bounded_json(&snapshot)
    }

    /// Return a cached snapshot without a network request.
    pub fn cached_snapshot_json(&self, project_id: &str) -> Result<String, String> {
        let project_id = Uuid::parse_str(project_id)
            .map_err(|error| format!("invalid project_id: {error}"))?;
        let snapshot = self
            .core
            .cached_snapshot(project_id)
            .ok_or_else(|| "snapshot is not cached".to_owned())?;
        bounded_json(&snapshot)
    }
}

impl Drop for HostClient {
    fn drop(&mut self) {
        self.shutdown.cancel();
    }
}

fn bounded_json<T: serde::Serialize>(value: &T) -> Result<String, String> {
    let text = serde_json::to_string(value).map_err(|error| error.to_string())?;
    if text.len() > MAX_HOST_JSON_BYTES {
        return Err(format!(
            "json_response exceeds {MAX_HOST_JSON_BYTES} bytes: {}",
            text.len()
        ));
    }
    Ok(text)
}
