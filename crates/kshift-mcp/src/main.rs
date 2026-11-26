use anyhow::Result;
use kshift_mcp::{run_stdio, KshiftBackend};

#[tokio::main]
async fn main() -> Result<()> {
    let backend = KshiftBackend::from_env().await?;
    run_stdio(backend).await
}
