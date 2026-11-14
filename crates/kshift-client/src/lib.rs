#![forbid(unsafe_code)]
#![deny(missing_docs)]

//! Kshift Rust client.
//!
//! The client owns TLS transport, authentication metadata, deadlines,
//! cancellation, bounded retries, normalized snapshots, revision tracking,
//! and cache reset behavior. Swift hosts consume this crate through
//! `kshift-ffi`, not directly.

mod cache;
mod client;
mod config;
mod error;
mod retry;
mod secret;

pub use cache::{AttachmentCache, CacheStats, EventApplyResult, SnapshotCache};
pub use client::{
    ClientEvent, CommandOutcome, KshiftClient, PlanDepthSession, ProjectSummary, ReconnectNotice,
    ResetNotice, WatchExit,
};
pub use config::{ClientConfig, RetryPolicy, DEFAULT_DEADLINE, MAX_DEADLINE, MAX_RESPONSE_BYTES};
pub use error::{ClientError, ClientErrorView, ConflictDetails};
pub use retry::jittered_retry_delay;
pub use secret::AuthToken;
