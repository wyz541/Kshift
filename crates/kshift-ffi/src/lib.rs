use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::sync::Mutex;

use kshift_client::KshiftClient;

const SCHEMA_VERSION: u32 = 1;

pub struct KshiftClientHandle {
    client: Mutex<KshiftClient>,
}

#[unsafe(no_mangle)]
pub extern "C" fn kshift_ffi_schema_version() -> u32 {
    SCHEMA_VERSION
}

#[unsafe(no_mangle)]
pub extern "C" fn kshift_client_new() -> *mut KshiftClientHandle {
    catch_unwind(AssertUnwindSafe(|| {
        Box::into_raw(Box::new(KshiftClientHandle {
            client: Mutex::new(KshiftClient::new()),
        }))
    }))
    .unwrap_or(ptr::null_mut())
}

/// Releases a client handle returned by `kshift_client_new`.
///
/// # Safety
/// `handle` must be null or a live pointer returned by `kshift_client_new`.
/// The caller must not use the handle after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kshift_client_free(handle: *mut KshiftClientHandle) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: The caller transfers ownership back exactly once.
        unsafe {
            drop(Box::from_raw(handle));
        }
    }));
}

/// Returns the project list as a Rust-owned JSON C string.
///
/// # Safety
/// A non-null `handle` must remain live for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kshift_client_projects_json(
    handle: *const KshiftClientHandle,
) -> *mut c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees a live handle for this call.
        let handle = unsafe { handle.as_ref() }.ok_or_else(handle_required_error)?;
        let client = handle
            .client
            .lock()
            .map_err(|_| "客户端锁已损坏。".to_string())?;
        Ok(client.projects_json())
    })
}

/// Returns one project snapshot as a Rust-owned JSON C string.
///
/// # Safety
/// A non-null `handle` must remain live. `project_id` must be null or a
/// valid nul-terminated UTF-8 C string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kshift_client_snapshot_json(
    handle: *const KshiftClientHandle,
    project_id: *const c_char,
) -> *mut c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees a live handle and a valid C string.
        let handle = unsafe { handle.as_ref() }.ok_or_else(handle_required_error)?;
        let project_id = unsafe { c_string(project_id)? };
        let client = handle
            .client
            .lock()
            .map_err(|_| "客户端锁已损坏。".to_string())?;
        Ok(client.snapshot_json(&project_id))
    })
}

/// Executes one command and returns a Rust-owned JSON C string.
///
/// # Safety
/// A non-null `handle` must remain live. `project_id` and `request_json`
/// must be null or valid nul-terminated UTF-8 C strings.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kshift_client_execute_json(
    handle: *mut KshiftClientHandle,
    project_id: *const c_char,
    request_json: *const c_char,
) -> *mut c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees a live handle and valid C strings.
        let handle = unsafe { handle.as_ref() }.ok_or_else(handle_required_error)?;
        let project_id = unsafe { c_string(project_id)? };
        let request_json = unsafe { c_string(request_json)? };
        let mut client = handle
            .client
            .lock()
            .map_err(|_| "客户端锁已损坏。".to_string())?;
        Ok(client.execute_json(&project_id, &request_json))
    })
}

/// Releases a string returned by this library.
///
/// # Safety
/// `value` must be null or a pointer returned by a Kshift FFI function.
/// The caller must not use the string after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kshift_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: The pointer came from CString::into_raw in this module.
        unsafe {
            drop(CString::from_raw(value));
        }
    }));
}

fn ffi_string<F>(operation: F) -> *mut c_char
where
    F: FnOnce() -> Result<String, String>,
{
    let result = catch_unwind(AssertUnwindSafe(operation));
    let json = match result {
        Ok(Ok(value)) => value,
        Ok(Err(message)) => error_json("ffi_error", &message),
        Err(_) => error_json("panic_caught", "FFI 调用发生 panic。"),
    };
    CString::new(json)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

unsafe fn c_string(value: *const c_char) -> Result<String, String> {
    if value.is_null() {
        return Err("C 字符串为空。".into());
    }
    // SAFETY: The caller guarantees a valid, nul-terminated C string.
    let value = unsafe { CStr::from_ptr(value) };
    value
        .to_str()
        .map(str::to_string)
        .map_err(|_| "C 字符串不是合法 UTF-8。".into())
}

fn handle_required_error() -> String {
    "客户端 handle 为空。".into()
}

fn error_json(code: &str, message: &str) -> String {
    serde_json::json!({
        "ok": false,
        "error": {
            "code": code,
            "message": message
        }
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn take_string(value: *mut c_char) -> String {
        assert!(!value.is_null());
        // SAFETY: Test owns the returned C string and frees it immediately.
        unsafe {
            let result = CStr::from_ptr(value).to_string_lossy().into_owned();
            kshift_string_free(value);
            result
        }
    }

    #[test]
    fn ffi_smoke_test() {
        let handle = kshift_client_new();
        assert!(!handle.is_null());
        // SAFETY: The handle is live for the duration of this test.
        let projects = take_string(unsafe { kshift_client_projects_json(handle) });
        assert!(projects.contains("Launch Room"));
        let project = CString::new("project-focus-2026").unwrap();
        // SAFETY: All pointers are valid and owned by the test.
        let snapshot =
            take_string(unsafe { kshift_client_snapshot_json(handle, project.as_ptr()) });
        assert!(snapshot.contains("task-launch-brief"));
        // SAFETY: The handle is freed exactly once.
        unsafe {
            kshift_client_free(handle);
        }
    }

    #[test]
    fn null_handle_returns_error_json() {
        // SAFETY: The function accepts a null pointer and must handle it.
        let response =
            take_string(unsafe { kshift_client_snapshot_json(ptr::null(), ptr::null()) });
        assert!(response.contains("ffi_error"));
    }
}
