#![deny(missing_docs)]
#![allow(unsafe_code)]

//! Bounded C ABI for the Kshift Rust client.
//!
//! Opaque handle values are registry identifiers. The C caller must never
//! dereference them. All exported functions catch panics and return a status
//! code. JSON buffers are owned by Rust and released with `kshift_buffer_free`.

mod buffer;
mod command;
mod error;
mod queue;
mod registry;

use std::ffi::{c_char, c_void};
use std::ptr;
use std::sync::Arc;
use std::time::Duration;

use domain::Change;
use kshift_client::{
    AuthToken, ClientConfig, ClientEvent, KshiftClient, ReconnectNotice, ResetNotice,
    DEFAULT_DEADLINE, MAX_RESPONSE_BYTES,
};
use serde_json::json;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use buffer::{copy_slice, free_buffer, write_buffer, KshiftBuffer, KshiftSlice};
use error::{run, FfiError, KshiftStatus};
use queue::ByteQueue;
use registry::{ClientSlot, SubscriptionSlot};

const MAX_ENDPOINT_BYTES: usize = 2048;
const MAX_CA_BYTES: usize = 1024 * 1024;
const MAX_TOKEN_BYTES: usize = 8192;
const MAX_COMMAND_BYTES: usize = 2 * 1024 * 1024;
const MAX_SNAPSHOT_BYTES: usize = 16 * 1024 * 1024;
const MAX_LIST_BYTES: usize = 2 * 1024 * 1024;
const MAX_EXECUTE_BYTES: usize = 2 * 1024 * 1024;
const MAX_STREAM_ITEM_BYTES: usize = 16 * 1024 * 1024;
const MAX_ATTACHMENT_BYTES: usize = 256 * 1024 * 1024;
const EVENT_QUEUE_ITEMS: usize = 64;
const EVENT_QUEUE_BYTES: usize = 32 * 1024 * 1024;

/// Client configuration passed by value. Slices are borrowed only for this call.
#[repr(C)]
pub struct KshiftClientConfig {
    endpoint_utf8: KshiftSlice,
    ca_pem: KshiftSlice,
    tls_domain_utf8: KshiftSlice,
    default_deadline_ms: u64,
    max_response_bytes: usize,
}

/// Create a client handle. The first RPC establishes the TLS connection.
#[no_mangle]
pub extern "C" fn kshift_client_create(
    config: *const KshiftClientConfig,
    out_client: *mut *mut c_void,
) -> KshiftStatus {
    run(|| {
        let out_client = checked_output(out_client)?;
        unsafe {
            out_client.write(ptr::null_mut());
        }
        let config = read_config(config)?;
        let runtime = registry::new_runtime()?;
        let core = Arc::new(runtime.block_on(async { KshiftClient::new(config) })?);
        let slot = Arc::new(ClientSlot {
            runtime,
            core,
            shutdown: CancellationToken::new(),
        });
        let id = registry::insert_client(slot);
        unsafe {
            out_client.write(registry::id_handle(id));
        }
        Ok(())
    })
}

/// Destroy a client and all subscriptions owned by that client.
#[no_mangle]
pub extern "C" fn kshift_client_destroy(client: *mut c_void) -> KshiftStatus {
    run(|| {
        let id = registry::handle_id(client).ok_or(FfiError::InvalidHandle)?;
        let slot = registry::remove_client(id)?;
        slot.shutdown.cancel();
        for subscription in registry::remove_subscriptions_for_client(id) {
            subscription.shutdown();
        }
        Ok(())
    })
}

/// Replace the client bearer token.
#[no_mangle]
pub extern "C" fn kshift_client_update_token(
    client: *mut c_void,
    token_utf8: KshiftSlice,
) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        let token = read_utf8(token_utf8, "token", MAX_TOKEN_BYTES, false)?;
        let token = AuthToken::new(token)?;
        slot.runtime.block_on(slot.core.set_token(token));
        Ok(())
    })
}

/// Clear the token and all business caches.
#[no_mangle]
pub extern "C" fn kshift_client_clear_token(client: *mut c_void) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        slot.runtime.block_on(slot.core.clear_token());
        Ok(())
    })
}

/// Clear every project snapshot and attachment cache.
#[no_mangle]
pub extern "C" fn kshift_client_clear_caches(client: *mut c_void) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        slot.core.clear_caches();
        Ok(())
    })
}

/// Clear one project's snapshot cache.
#[no_mangle]
pub extern "C" fn kshift_client_clear_project_cache(
    client: *mut c_void,
    project_id_utf8: KshiftSlice,
) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        let project_id = read_project_id(project_id_utf8)?;
        slot.core.clear_project(project_id);
        Ok(())
    })
}

/// Cache one attachment by SHA-256 key.
#[no_mangle]
pub extern "C" fn kshift_client_cache_attachment(
    client: *mut c_void,
    sha256_hex_utf8: KshiftSlice,
    bytes: KshiftSlice,
) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        let key = read_utf8(sha256_hex_utf8, "sha256_hex", 64, false)?;
        let bytes = unsafe { copy_slice(bytes, "attachment", MAX_ATTACHMENT_BYTES)? };
        slot.core.cache_attachment(&key, &bytes)?;
        Ok(())
    })
}

/// Read one cached attachment by SHA-256 key.
///
/// # Safety
/// `out_bytes` must be null or writable storage for one output buffer.
#[no_mangle]
pub unsafe extern "C" fn kshift_client_get_cached_attachment(
    client: *mut c_void,
    sha256_hex_utf8: KshiftSlice,
    out_bytes: *mut KshiftBuffer,
) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        let key = read_utf8(sha256_hex_utf8, "sha256_hex", 64, false)?;
        let bytes = slot
            .core
            .cached_attachment(&key)
            .ok_or_else(|| FfiError::Client(kshift_client::ClientError::CacheMiss(key.clone())))?;
        write_buffer(bytes, out_bytes)
    })
}

/// Clear the attachment cache.
#[no_mangle]
pub extern "C" fn kshift_client_clear_attachment_cache(client: *mut c_void) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        slot.core.clear_attachment_cache();
        Ok(())
    })
}

/// List projects visible to the current identity.
#[no_mangle]
pub extern "C" fn kshift_client_list_projects(
    client: *mut c_void,
    deadline_ms: u64,
    cancel: *mut c_void,
    out_json: *mut KshiftBuffer,
) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        let deadline = deadline(deadline_ms);
        let cancel = resolve_cancel(cancel)?;
        let projects = slot
            .runtime
            .block_on(slot.core.list_projects(Some(deadline), &cancel))?;
        write_bounded_json(&projects, out_json, MAX_LIST_BYTES)
    })
}

/// Fetch a fresh project snapshot and update the memory cache.
#[no_mangle]
pub extern "C" fn kshift_client_get_snapshot(
    client: *mut c_void,
    project_id_utf8: KshiftSlice,
    deadline_ms: u64,
    cancel: *mut c_void,
    out_json: *mut KshiftBuffer,
) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        let project_id = read_project_id(project_id_utf8)?;
        let cancel = resolve_cancel(cancel)?;
        let snapshot = slot.runtime.block_on(slot.core.get_snapshot(
            project_id,
            Some(deadline(deadline_ms)),
            &cancel,
        ))?;
        write_bounded_json(&snapshot, out_json, MAX_SNAPSHOT_BYTES)
    })
}

/// Return a cached project snapshot without a network request.
#[no_mangle]
pub extern "C" fn kshift_client_get_cached_snapshot(
    client: *mut c_void,
    project_id_utf8: KshiftSlice,
    out_json: *mut KshiftBuffer,
) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        let project_id = read_project_id(project_id_utf8)?;
        let snapshot =
            slot.core
                .cached_snapshot(project_id)
                .ok_or(kshift_client::ClientError::CacheMiss(
                    project_id.to_string(),
                ))?;
        write_bounded_json(&snapshot, out_json, MAX_SNAPSHOT_BYTES)
    })
}

/// Execute one typed command.
///
/// # Safety
/// `command_json` must describe readable bytes for the call duration and
/// `out_json` must be null or writable storage for one output buffer.
#[no_mangle]
pub unsafe extern "C" fn kshift_client_execute_command(
    client: *mut c_void,
    command_json: KshiftSlice,
    deadline_ms: u64,
    cancel: *mut c_void,
    out_json: *mut KshiftBuffer,
) -> KshiftStatus {
    run(|| {
        let slot = client_slot(client)?;
        let bytes = unsafe { copy_slice(command_json, "command_json", MAX_COMMAND_BYTES)? };
        std::str::from_utf8(&bytes).map_err(|_| FfiError::InvalidUtf8)?;
        let command = command::command_from_json(&bytes)?;
        let cancel = resolve_cancel(cancel)?;
        let outcome = slot.runtime.block_on(slot.core.execute_command(
            &command,
            Some(deadline(deadline_ms)),
            &cancel,
        ))?;
        let bytes = command_outcome_json(&outcome)?;
        if bytes.len() > MAX_EXECUTE_BYTES {
            return Err(FfiError::MessageTooLarge {
                field: "execute_response",
                actual: bytes.len(),
                limit: MAX_EXECUTE_BYTES,
            });
        }
        unsafe { write_buffer(bytes, out_json) }
    })
}

/// Start a bounded event subscription for one project.
#[no_mangle]
pub extern "C" fn kshift_client_watch_project(
    client: *mut c_void,
    project_id_utf8: KshiftSlice,
    since_revision: u64,
    cancel: *mut c_void,
    out_subscription: *mut *mut c_void,
) -> KshiftStatus {
    run(|| {
        let out_subscription = checked_output(out_subscription)?;
        unsafe {
            out_subscription.write(ptr::null_mut());
        }
        let client_id = registry::handle_id(client).ok_or(FfiError::InvalidHandle)?;
        let slot = client_slot(client)?;
        let project_id = read_project_id(project_id_utf8)?;
        let parent = resolve_cancel(cancel)?;
        let watch_cancel = parent.child_token();
        let queue = Arc::new(ByteQueue::new(EVENT_QUEUE_ITEMS, EVENT_QUEUE_BYTES));
        let (tx, mut rx) = mpsc::channel::<ClientEvent>(8);

        let encoder_queue = queue.clone();
        let encoder_cancel = watch_cancel.clone();
        let encoder = slot.runtime.spawn(async move {
            while let Some(event) = rx.recv().await {
                match client_event_json(&event) {
                    Ok(bytes) if bytes.len() <= MAX_STREAM_ITEM_BYTES => {
                        if !encoder_queue.push(bytes).await {
                            encoder_cancel.cancel();
                            break;
                        }
                    }
                    _ => {
                        encoder_cancel.cancel();
                        break;
                    }
                }
            }
            encoder_queue.close();
        });

        let watch_queue = queue.clone();
        let core = slot.core.clone();
        let subscription_cancel = watch_cancel.clone();
        let watch = slot.runtime.spawn(async move {
            let initial_revision = (since_revision > 0).then_some(since_revision);
            let _ = core
                .watch_project(project_id, initial_revision, watch_cancel, tx)
                .await;
            watch_queue.close();
        });

        let subscription = Arc::new(SubscriptionSlot::new(
            client_id,
            slot.runtime.clone(),
            subscription_cancel,
            queue,
            vec![encoder, watch],
        ));
        let id = registry::insert_subscription(subscription);
        unsafe {
            out_subscription.write(registry::id_handle(id));
        }
        Ok(())
    })
}

/// Poll one JSON client event. A zero timeout polls without waiting.
///
/// # Safety
/// `subscription` must be a live handle and `out_json` must point to writable
/// storage initialized to zero or to a previously freed buffer.
#[no_mangle]
pub unsafe extern "C" fn kshift_subscription_next(
    subscription: *mut c_void,
    timeout_ms: u64,
    out_json: *mut KshiftBuffer,
) -> KshiftStatus {
    run(|| {
        let id = registry::handle_id(subscription).ok_or(FfiError::InvalidHandle)?;
        let slot = registry::subscription(id)?;
        let timeout = Some(Duration::from_millis(timeout_ms));
        match slot.runtime.block_on(slot.queue.pop(timeout)) {
            Ok(Some(bytes)) => unsafe { write_buffer(bytes, out_json) },
            Ok(None) => Err(FfiError::Client(
                kshift_client::ClientError::DeadlineExceeded,
            )),
            Err(()) => Err(FfiError::InvalidState(
                "subscription is closed and has no pending events".to_owned(),
            )),
        }
    })
}

/// Destroy a subscription and cancel its worker tasks.
#[no_mangle]
pub extern "C" fn kshift_subscription_destroy(subscription: *mut c_void) -> KshiftStatus {
    run(|| {
        let id = registry::handle_id(subscription).ok_or(FfiError::InvalidHandle)?;
        let slot = registry::remove_subscription(id)?;
        slot.shutdown();
        Ok(())
    })
}

/// Create a cancel token.
#[no_mangle]
pub extern "C" fn kshift_cancel_token_create(out_cancel: *mut *mut c_void) -> KshiftStatus {
    run(|| {
        let out_cancel = checked_output(out_cancel)?;
        unsafe {
            out_cancel.write(ptr::null_mut());
        }
        let id = registry::insert_cancel(CancellationToken::new());
        unsafe {
            out_cancel.write(registry::id_handle(id));
        }
        Ok(())
    })
}

/// Cancel a cancel token and all child operations.
#[no_mangle]
pub extern "C" fn kshift_cancel_token_cancel(cancel: *mut c_void) -> KshiftStatus {
    run(|| {
        let id = registry::handle_id(cancel).ok_or(FfiError::InvalidHandle)?;
        registry::cancel_token(id)?.cancel();
        Ok(())
    })
}

/// Destroy a cancel token.
#[no_mangle]
pub extern "C" fn kshift_cancel_token_destroy(cancel: *mut c_void) -> KshiftStatus {
    run(|| {
        let id = registry::handle_id(cancel).ok_or(FfiError::InvalidHandle)?;
        registry::remove_cancel(id)?;
        Ok(())
    })
}

/// Copy the last error JSON for the current thread.
///
/// # Safety
/// `out_json` must point to writable storage initialized to zero or to a
/// previously freed buffer.
#[no_mangle]
pub unsafe extern "C" fn kshift_last_error_json(out_json: *mut KshiftBuffer) -> KshiftStatus {
    match error::take_last_error_json() {
        Some(bytes) => match unsafe { write_buffer(bytes, out_json) } {
            Ok(()) => KshiftStatus::Ok,
            Err(error) => error.status(),
        },
        None => KshiftStatus::InvalidState,
    }
}

/// Free one JSON buffer. The caller must not reuse the buffer after this call.
///
/// # Safety
/// `buffer` must point to a valid `KshiftBuffer` owned by this library and must
/// be freed at most once.
#[no_mangle]
pub unsafe extern "C" fn kshift_buffer_free(buffer: *mut KshiftBuffer) -> KshiftStatus {
    match unsafe { free_buffer(buffer) } {
        Ok(()) => KshiftStatus::Ok,
        Err(error) => error.status(),
    }
}

/// Return a stable status name without allocating.
#[no_mangle]
pub extern "C" fn kshift_status_name(status: KshiftStatus) -> *const c_char {
    error::status_name(status)
}

fn checked_output<T>(output: *mut T) -> Result<*mut T, FfiError> {
    if output.is_null() {
        Err(FfiError::InvalidArgument(
            "output pointer is null".to_owned(),
        ))
    } else {
        Ok(output)
    }
}

fn client_slot(client: *mut c_void) -> Result<Arc<ClientSlot>, FfiError> {
    let id = registry::handle_id(client).ok_or(FfiError::InvalidHandle)?;
    registry::client(id)
}

fn resolve_cancel(cancel: *mut c_void) -> Result<CancellationToken, FfiError> {
    let Some(id) = registry::handle_id(cancel) else {
        return Ok(CancellationToken::new());
    };
    registry::cancel_token(id)
}

fn read_config(config: *const KshiftClientConfig) -> Result<ClientConfig, FfiError> {
    if config.is_null() {
        return Err(FfiError::InvalidArgument("config is null".to_owned()));
    }
    let config = unsafe { &*config };
    let endpoint = read_utf8(config.endpoint_utf8, "endpoint", MAX_ENDPOINT_BYTES, false)?;
    let ca_pem = unsafe { copy_slice(config.ca_pem, "ca_pem", MAX_CA_BYTES)? };
    let tls_domain = read_utf8(config.tls_domain_utf8, "tls_domain", 255, true)?;
    let tls_domain = (!tls_domain.is_empty()).then_some(tls_domain);
    let default_deadline = if config.default_deadline_ms == 0 {
        DEFAULT_DEADLINE
    } else {
        Duration::from_millis(config.default_deadline_ms)
    };
    let max_response_bytes = if config.max_response_bytes == 0 {
        MAX_RESPONSE_BYTES
    } else {
        config.max_response_bytes
    };
    Ok(ClientConfig::new(
        endpoint,
        ca_pem,
        tls_domain,
        default_deadline,
        max_response_bytes,
    )?)
}

fn read_utf8(
    slice: KshiftSlice,
    field: &'static str,
    max_bytes: usize,
    allow_empty: bool,
) -> Result<String, FfiError> {
    let bytes = unsafe { copy_slice(slice, field, max_bytes)? };
    let value = String::from_utf8(bytes).map_err(|_| FfiError::InvalidUtf8)?;
    if !allow_empty && value.is_empty() {
        return Err(FfiError::InvalidArgument(format!(
            "{field} must not be empty"
        )));
    }
    Ok(value)
}

fn read_project_id(slice: KshiftSlice) -> Result<Uuid, FfiError> {
    let value = read_utf8(slice, "project_id", 128, false)?;
    Uuid::parse_str(&value)
        .map_err(|_| FfiError::InvalidArgument("project_id must be a UUID".to_owned()))
}

fn deadline(value: u64) -> Duration {
    if value == 0 {
        DEFAULT_DEADLINE
    } else {
        Duration::from_millis(value)
    }
}

fn write_bounded_json<T: serde::Serialize>(
    value: &T,
    output: *mut KshiftBuffer,
    limit: usize,
) -> Result<(), FfiError> {
    let bytes = serde_json::to_vec(value).map_err(|_| FfiError::Internal)?;
    if bytes.len() > limit {
        return Err(FfiError::MessageTooLarge {
            field: "json_response",
            actual: bytes.len(),
            limit,
        });
    }
    unsafe { write_buffer(bytes, output) }
}

fn client_event_json(event: &ClientEvent) -> Result<Vec<u8>, FfiError> {
    let value = match event {
        ClientEvent::Snapshot(snapshot) => json!({"kind": "snapshot", "value": snapshot}),
        ClientEvent::Change(event) => json!({
            "kind": "change",
            "value": change_event_value(event),
        }),
        ClientEvent::ResetRequired(ResetNotice {
            project_id,
            current_revision,
            minimum_retained_revision,
            reason,
        }) => json!({
            "kind": "reset_required",
            "value": {
                "project_id": project_id,
                "current_revision": current_revision,
                "minimum_retained_revision": minimum_retained_revision,
                "reason": reason,
            }
        }),
        ClientEvent::Reconnecting(ReconnectNotice {
            attempt,
            retry_in_ms,
        }) => json!({
            "kind": "reconnecting",
            "value": {"attempt": attempt, "retry_in_ms": retry_in_ms}
        }),
        ClientEvent::Error(error) => json!({"kind": "error", "value": error}),
    };
    serde_json::to_vec(&value).map_err(|_| FfiError::Internal)
}

fn command_outcome_json(outcome: &kshift_client::CommandOutcome) -> Result<Vec<u8>, FfiError> {
    let value = json!({
        "command_id": outcome.command_id,
        "revision": outcome.revision,
        "event": change_event_value(&outcome.event),
    });
    serde_json::to_vec(&value).map_err(|_| FfiError::Internal)
}

fn change_event_value(event: &domain::ChangeEvent) -> serde_json::Value {
    json!({
        "project_id": event.project_id,
        "revision": event.revision,
        "schema_version": event.schema_version,
        "command_id": event.command_id,
        "occurred_at": event.occurred_at,
        "change": change_json(&event.change),
    })
}

fn change_json(change: &Change) -> serde_json::Value {
    match change {
        Change::ProjectUpserted { project } => json!({
            "type": "project_upserted",
            "value": {"project": project}
        }),
        Change::ProjectMemberUpserted { member } => json!({
            "type": "project_member_upserted",
            "value": {"member": member}
        }),
        Change::TaskCreated { task } => json!({
            "type": "task_created",
            "value": {"task": task}
        }),
        Change::TaskUpdated { task } => json!({
            "type": "task_updated",
            "value": {"task": task}
        }),
        Change::TaskDeleted { task_id } => json!({
            "type": "task_deleted",
            "value": {"task_id": task_id}
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::{run, KshiftStatus};

    fn config(endpoint: &str, ca: &[u8], domain: &str) -> KshiftClientConfig {
        KshiftClientConfig {
            endpoint_utf8: KshiftSlice {
                data: endpoint.as_ptr(),
                len: endpoint.len(),
            },
            ca_pem: KshiftSlice {
                data: ca.as_ptr(),
                len: ca.len(),
            },
            tls_domain_utf8: KshiftSlice {
                data: domain.as_ptr(),
                len: domain.len(),
            },
            default_deadline_ms: 1000,
            max_response_bytes: 16 * 1024 * 1024,
        }
    }

    #[test]
    fn create_call_destroy_and_stale_handle_are_explicit() {
        let ca = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/tls/ca.pem"
        ));
        let config = config("https://localhost:65535", ca, "localhost");
        let mut client = std::ptr::null_mut();
        assert_eq!(kshift_client_create(&config, &mut client), KshiftStatus::Ok);
        assert!(!client.is_null());

        let mut cancel = std::ptr::null_mut();
        assert_eq!(kshift_cancel_token_create(&mut cancel), KshiftStatus::Ok);
        assert_eq!(kshift_cancel_token_cancel(cancel), KshiftStatus::Ok);

        let project = project_id().to_string();
        let project_slice = KshiftSlice {
            data: project.as_ptr(),
            len: project.len(),
        };
        let mut buffer = KshiftBuffer::EMPTY;
        let status = kshift_client_get_cached_snapshot(client, project_slice, &mut buffer);
        assert_eq!(status, KshiftStatus::NotFound);

        assert_eq!(kshift_cancel_token_destroy(cancel), KshiftStatus::Ok);
        assert_eq!(
            kshift_cancel_token_destroy(cancel),
            KshiftStatus::InvalidHandle
        );
        assert_eq!(kshift_client_destroy(client), KshiftStatus::Ok);
        assert_eq!(kshift_client_destroy(client), KshiftStatus::InvalidHandle);
    }

    #[test]
    fn invalid_utf8_oversize_json_and_buffer_lifecycle_are_explicit() {
        let ca = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/tls/ca.pem"
        ));
        let config = config("https://localhost:65535", ca, "localhost");
        let mut client = std::ptr::null_mut();
        assert_eq!(kshift_client_create(&config, &mut client), KshiftStatus::Ok);

        let invalid = [0xff_u8, 0xfe];
        let status = unsafe {
            kshift_client_execute_command(
                client,
                KshiftSlice {
                    data: invalid.as_ptr(),
                    len: invalid.len(),
                },
                1000,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            )
        };
        assert_eq!(status, KshiftStatus::InvalidUtf8);

        let mut error_buffer = KshiftBuffer::EMPTY;
        assert_eq!(
            unsafe { kshift_last_error_json(&mut error_buffer) },
            KshiftStatus::Ok
        );
        assert!(!error_buffer.data.is_null());
        let error_json =
            unsafe { std::slice::from_raw_parts(error_buffer.data, error_buffer.len).to_vec() };
        assert!(String::from_utf8(error_json)
            .expect("error JSON")
            .contains("invalid_utf8"));
        assert_eq!(
            unsafe { kshift_buffer_free(&mut error_buffer) },
            KshiftStatus::Ok
        );
        assert!(error_buffer.data.is_null());
        assert_eq!(
            unsafe { kshift_buffer_free(&mut error_buffer) },
            KshiftStatus::Ok
        );

        let oversize = KshiftSlice {
            data: std::ptr::null(),
            len: MAX_COMMAND_BYTES + 1,
        };
        let mut output = KshiftBuffer::EMPTY;
        let status = unsafe {
            kshift_client_execute_command(client, oversize, 1000, std::ptr::null_mut(), &mut output)
        };
        assert_eq!(status, KshiftStatus::MessageTooLarge);

        let valid_utf8 = b"{not-json}";
        let status = unsafe {
            kshift_client_execute_command(
                client,
                KshiftSlice {
                    data: valid_utf8.as_ptr(),
                    len: valid_utf8.len(),
                },
                1000,
                std::ptr::null_mut(),
                &mut output,
            )
        };
        assert_eq!(status, KshiftStatus::InvalidArgument);

        assert_eq!(kshift_client_destroy(client), KshiftStatus::Ok);
    }

    #[test]
    fn attachment_cache_round_trips_bounded_bytes() {
        let ca = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/tls/ca.pem"
        ));
        let config = config("https://localhost:65535", ca, "localhost");
        let mut client = std::ptr::null_mut();
        assert_eq!(kshift_client_create(&config, &mut client), KshiftStatus::Ok);

        let key = "a".repeat(64);
        let bytes = b"attachment-bytes";
        let status = kshift_client_cache_attachment(
            client,
            KshiftSlice {
                data: key.as_ptr(),
                len: key.len(),
            },
            KshiftSlice {
                data: bytes.as_ptr(),
                len: bytes.len(),
            },
        );
        assert_eq!(status, KshiftStatus::Ok);

        let mut output = KshiftBuffer::EMPTY;
        let status = unsafe {
            kshift_client_get_cached_attachment(
                client,
                KshiftSlice {
                    data: key.as_ptr(),
                    len: key.len(),
                },
                &mut output,
            )
        };
        assert_eq!(status, KshiftStatus::Ok);
        let copied = unsafe { std::slice::from_raw_parts(output.data, output.len) };
        assert_eq!(copied, bytes);
        assert_eq!(unsafe { kshift_buffer_free(&mut output) }, KshiftStatus::Ok);
        assert_eq!(kshift_client_destroy(client), KshiftStatus::Ok);
    }

    #[test]
    fn panic_is_contained_at_the_boundary() {
        let status = run(|| panic!("test panic"));
        assert_eq!(status, KshiftStatus::Internal);
        let mut buffer = KshiftBuffer::EMPTY;
        assert_eq!(
            unsafe { kshift_last_error_json(&mut buffer) },
            KshiftStatus::Ok
        );
        let value = unsafe { std::slice::from_raw_parts(buffer.data, buffer.len) };
        assert!(String::from_utf8_lossy(value).contains("FFI panic contained"));
        assert_eq!(unsafe { kshift_buffer_free(&mut buffer) }, KshiftStatus::Ok);
    }

    fn project_id() -> Uuid {
        Uuid::from_u128(0x11111111_2222_4333_8444_555555555555)
    }
}
