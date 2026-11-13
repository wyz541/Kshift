use anyhow::Context;
use tracing_subscriber::{fmt, EnvFilter};

pub fn init(filter: &str) -> anyhow::Result<()> {
    let env_filter = EnvFilter::try_new(filter).context("RUST_LOG is invalid")?;
    fmt()
        .json()
        .with_env_filter(env_filter)
        .with_current_span(true)
        .with_span_list(true)
        .with_target(true)
        .with_ansi(false)
        .try_init()
        .map_err(|error| anyhow::anyhow!("failed to initialize tracing: {error}"))
}
