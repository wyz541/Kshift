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

use crate::error::FfiError;
use crate::{command, registry};

/// Maximum size of one host JSON response.
pub const MAX_HOST_JSON_BYTES: usize = MAX_RESPONSE_BYTES;

/// Maximum accepted size of one typed command envelope.
pub const MAX_HOST_COMMAND_BYTES: usize = crate::MAX_COMMAND_BYTES;

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
        let project_id =
            Uuid::parse_str(project_id).map_err(|error| format!("invalid project_id: {error}"))?;
        let cancel = CancellationToken::new();
        let snapshot = self
            .runtime
            .block_on(self.core.get_snapshot(project_id, None, &cancel))
            .map_err(|error| error.to_string())?;
        bounded_json(&snapshot)
    }

    /// Return a cached snapshot without a network request.
    pub fn cached_snapshot_json(&self, project_id: &str) -> Result<String, String> {
        let project_id =
            Uuid::parse_str(project_id).map_err(|error| format!("invalid project_id: {error}"))?;
        let snapshot = self
            .core
            .cached_snapshot(project_id)
            .ok_or_else(|| "snapshot is not cached".to_owned())?;
        bounded_json(&snapshot)
    }

    /// Execute one typed command and return the bounded command outcome JSON.
    ///
    /// The command envelope is validated by `kshift-ffi` and then by the Rust
    /// domain/client layer. Errors are returned as bounded JSON with the same
    /// `code`, `message`, `retryable` and conflict detail fields as the C ABI.
    /// This keeps version conflicts available to a Rust UI host without
    /// duplicating client or domain semantics.
    pub fn execute_command_json(&self, command_json: &str) -> Result<String, String> {
        if command_json.len() > MAX_HOST_COMMAND_BYTES {
            return Err(host_error_json(FfiError::MessageTooLarge {
                field: "command_json",
                actual: command_json.len(),
                limit: MAX_HOST_COMMAND_BYTES,
            }));
        }
        let command =
            command::command_from_json(command_json.as_bytes()).map_err(host_error_json)?;
        let cancel = CancellationToken::new();
        let outcome = self
            .runtime
            .block_on(self.core.execute_command(&command, None, &cancel))
            .map_err(|error| host_error_json(FfiError::Client(error)))?;
        let bytes = crate::command_outcome_json(&outcome).map_err(host_error_json)?;
        if bytes.len() > MAX_HOST_JSON_BYTES {
            return Err(host_error_json(FfiError::MessageTooLarge {
                field: "execute_response",
                actual: bytes.len(),
                limit: MAX_HOST_JSON_BYTES,
            }));
        }
        String::from_utf8(bytes).map_err(|_| host_error_json(FfiError::Internal))
    }
}

impl Drop for HostClient {
    fn drop(&mut self) {
        self.shutdown.cancel();
    }
}

fn host_error_json(error: FfiError) -> String {
    String::from_utf8(error.json()).unwrap_or_else(|_| {
        "{\"code\":\"internal\",\"message\":\"error encoding failed\",\"retryable\":false}"
            .to_owned()
    })
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

#[cfg(test)]
mod tests {
    use super::*;

    fn client() -> HostClient {
        let ca = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/tls/ca.pem"
        ));
        HostClient::connect(
            "https://localhost:65535",
            ca.to_vec(),
            Some("localhost".into()),
            None,
        )
        .expect("host client")
    }

    fn error_code(value: &str) -> String {
        serde_json::from_str::<serde_json::Value>(value)
            .expect("error JSON")
            .get("code")
            .and_then(serde_json::Value::as_str)
            .expect("error code")
            .to_owned()
    }

    const VALID_COMMAND: &str = r#"{
        "client_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        "command_id": "99999999-8888-4777-8666-555555555555",
        "project_id": "11111111-2222-4333-8444-555555555555",
        "expected_project_revision": 7,
        "command": {
            "type": "update_task",
            "value": {
                "task_id": "22222222-2222-4222-8222-222222222222",
                "expected_entity_version": 3,
                "title": "Updated title"
            }
        }
    }"#;

    #[test]
    fn command_input_boundary_is_bounded_json() {
        let client = client();
        let oversize = "x".repeat(MAX_HOST_COMMAND_BYTES + 1);
        let error = client
            .execute_command_json(&oversize)
            .expect_err("oversize command is rejected");
        assert_eq!(error_code(&error), "message_too_large");

        let error = client
            .execute_command_json(r#"{"unknown":true}"#)
            .expect_err("unknown envelope field is rejected");
        assert_eq!(error_code(&error), "invalid_argument");
    }

    #[test]
    fn typed_command_validation_precedes_transport() {
        let client = client();
        let error = client
            .execute_command_json(VALID_COMMAND)
            .expect_err("missing token is rejected before transport");
        assert_eq!(error_code(&error), "unauthenticated");

        let invalid_uuid =
            VALID_COMMAND.replace("22222222-2222-4222-8222-222222222222", "not-a-uuid");
        let error = client
            .execute_command_json(&invalid_uuid)
            .expect_err("invalid task UUID is rejected");
        assert_eq!(error_code(&error), "invalid_argument");
    }
}
