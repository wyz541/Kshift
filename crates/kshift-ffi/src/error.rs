use std::cell::RefCell;
use std::ffi::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

use domain::DomainError;
use kshift_client::{ClientError, ClientErrorView};
use serde_json::json;

/// Stable C status codes.
#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum KshiftStatus {
    Ok = 0,
    InvalidArgument = 1,
    InvalidHandle = 2,
    InvalidState = 3,
    InvalidUtf8 = 4,
    MessageTooLarge = 5,
    DeadlineExceeded = 6,
    Cancelled = 7,
    Unauthenticated = 8,
    PermissionDenied = 9,
    NotFound = 10,
    Conflict = 11,
    ResetRequired = 12,
    ResourceExhausted = 13,
    Unavailable = 14,
    ProtocolError = 15,
    Internal = 16,
}

#[derive(Debug)]
pub enum FfiError {
    Client(ClientError),
    InvalidArgument(String),
    InvalidHandle,
    InvalidState(String),
    InvalidUtf8,
    MessageTooLarge {
        field: &'static str,
        actual: usize,
        limit: usize,
    },
    Internal,
}

impl From<ClientError> for FfiError {
    fn from(value: ClientError) -> Self {
        Self::Client(value)
    }
}

impl From<DomainError> for FfiError {
    fn from(value: DomainError) -> Self {
        Self::Client(ClientError::Domain(value))
    }
}

impl FfiError {
    pub fn status(&self) -> KshiftStatus {
        match self {
            Self::Client(error) => status_for_client(error),
            Self::InvalidArgument(_) => KshiftStatus::InvalidArgument,
            Self::InvalidHandle => KshiftStatus::InvalidHandle,
            Self::InvalidState(_) => KshiftStatus::InvalidState,
            Self::InvalidUtf8 => KshiftStatus::InvalidUtf8,
            Self::MessageTooLarge { .. } => KshiftStatus::MessageTooLarge,
            Self::Internal => KshiftStatus::Internal,
        }
    }

    fn json(&self) -> Vec<u8> {
        let value = match self {
            Self::Client(error) => {
                serde_json::to_value(error.view()).unwrap_or_else(|_| plain_error(&error.view()))
            }
            Self::InvalidArgument(message) => plain_json("invalid_argument", message),
            Self::InvalidHandle => plain_json(
                "invalid_handle",
                "handle is invalid or was already destroyed",
            ),
            Self::InvalidState(message) => plain_json("invalid_state", message),
            Self::InvalidUtf8 => plain_json("invalid_utf8", "input is not valid UTF-8"),
            Self::MessageTooLarge {
                field,
                actual,
                limit,
            } => plain_json(
                "message_too_large",
                &format!("{field} is {actual} bytes; limit is {limit} bytes"),
            ),
            Self::Internal => plain_json("internal", "FFI panic contained"),
        };
        serde_json::to_vec(&value).unwrap_or_else(|_| {
            b"{\"code\":\"internal\",\"message\":\"error encoding failed\",\"retryable\":false}"
                .to_vec()
        })
    }
}

thread_local! {
    static LAST_ERROR: RefCell<Option<Vec<u8>>> = const { RefCell::new(None) };
}

pub fn run<F>(operation: F) -> KshiftStatus
where
    F: FnOnce() -> Result<(), FfiError>,
{
    clear_last_error();
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(Ok(())) => KshiftStatus::Ok,
        Ok(Err(error)) => {
            store_last_error(error.json());
            error.status()
        }
        Err(_) => {
            store_last_error(FfiError::Internal.json());
            KshiftStatus::Internal
        }
    }
}

pub fn take_last_error_json() -> Option<Vec<u8>> {
    LAST_ERROR.with(|slot| slot.borrow().clone())
}

pub fn clear_last_error() {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = None);
}

fn store_last_error(value: Vec<u8>) {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some(value));
}

fn plain_json(code: &str, message: &str) -> serde_json::Value {
    json!({
        "code": code,
        "message": message,
        "retryable": false
    })
}

fn plain_error(view: &ClientErrorView) -> serde_json::Value {
    plain_json(&view.code, &view.message)
}

fn status_for_client(error: &ClientError) -> KshiftStatus {
    match error {
        ClientError::InvalidConfig(_)
        | ClientError::InvalidArgument(_)
        | ClientError::Domain(_) => KshiftStatus::InvalidArgument,
        ClientError::AuthenticationRequired | ClientError::Unauthenticated => {
            KshiftStatus::Unauthenticated
        }
        ClientError::PermissionDenied => KshiftStatus::PermissionDenied,
        ClientError::NotFound(_) => KshiftStatus::NotFound,
        ClientError::Conflict(_) => KshiftStatus::Conflict,
        ClientError::ResetRequired { .. } => KshiftStatus::ResetRequired,
        ClientError::AlreadyExists(_) => KshiftStatus::Conflict,
        ClientError::ResourceExhausted(_) => KshiftStatus::ResourceExhausted,
        ClientError::FailedPrecondition(_) => KshiftStatus::InvalidState,
        ClientError::Unavailable(_) => KshiftStatus::Unavailable,
        ClientError::DeadlineExceeded => KshiftStatus::DeadlineExceeded,
        ClientError::Cancelled => KshiftStatus::Cancelled,
        ClientError::Protocol(_) | ClientError::ResponseTooLarge { .. } => {
            KshiftStatus::ProtocolError
        }
        ClientError::CacheMiss(_) => KshiftStatus::NotFound,
        ClientError::Internal(_) => KshiftStatus::Internal,
    }
}

pub fn status_name(status: KshiftStatus) -> *const c_char {
    let bytes: &'static [u8] = match status {
        KshiftStatus::Ok => b"OK\0",
        KshiftStatus::InvalidArgument => b"INVALID_ARGUMENT\0",
        KshiftStatus::InvalidHandle => b"INVALID_HANDLE\0",
        KshiftStatus::InvalidState => b"INVALID_STATE\0",
        KshiftStatus::InvalidUtf8 => b"INVALID_UTF8\0",
        KshiftStatus::MessageTooLarge => b"MESSAGE_TOO_LARGE\0",
        KshiftStatus::DeadlineExceeded => b"DEADLINE_EXCEEDED\0",
        KshiftStatus::Cancelled => b"CANCELLED\0",
        KshiftStatus::Unauthenticated => b"UNAUTHENTICATED\0",
        KshiftStatus::PermissionDenied => b"PERMISSION_DENIED\0",
        KshiftStatus::NotFound => b"NOT_FOUND\0",
        KshiftStatus::Conflict => b"CONFLICT\0",
        KshiftStatus::ResetRequired => b"RESET_REQUIRED\0",
        KshiftStatus::ResourceExhausted => b"RESOURCE_EXHAUSTED\0",
        KshiftStatus::Unavailable => b"UNAVAILABLE\0",
        KshiftStatus::ProtocolError => b"PROTOCOL_ERROR\0",
        KshiftStatus::Internal => b"INTERNAL\0",
    };
    bytes.as_ptr().cast()
}
