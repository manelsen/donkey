//! Stdio transport: spawn a child process and communicate via JSON-RPC over stdin/stdout.

use std::{
    collections::HashMap,
    process::Stdio,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
};

use {
    tokio::{
        io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
        process::{Child, Command},
        sync::{Mutex, oneshot},
    },
    tracing::{debug, info, trace, warn},
};

use crate::{
    error::{Context, Error, Result},
    traits::McpTransport,
    types::{JsonRpcNotification, JsonRpcRequest, JsonRpcResponse},
};

/// Stdio-based transport for an MCP server process.
pub struct StdioTransport {
    ...
}

impl StdioTransport {
    /// Spawn the server process and start the reader loop.
    pub async fn spawn(
        command: &str,
        args: &[String],
        env: &HashMap<String, String>,
    ) -> Result<Arc<Self>> {
}

#[async_trait::async_trait]
impl McpTransport for StdioTransport {
    async fn request(
        &self,
        method: &str,
        params: Option<serde_json::Value>,
    ) -> Result<JsonRpcResponse> {

    async fn notify(&self, method: &str, params: Option<serde_json::Value>) -> Result<()> {
    ...
}

    async fn is_alive(&self) -> bool {
    ...
}

    async fn kill(&self) {
    ...
}
}

#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_spawn_nonexistent_command() {
    ...
}
}
