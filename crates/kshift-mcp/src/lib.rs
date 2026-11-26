//! Kshift MCP stdio adapter.
//!
//! The adapter is intentionally read-only in its first slice. It uses the
//! shared Rust client for authentication, transport, retries, and project
//! authorization instead of duplicating Core API business logic.

mod backend;
mod protocol;

pub use backend::{KshiftBackend, McpBackend, McpError};
pub use protocol::{run_stdio, McpServer};
