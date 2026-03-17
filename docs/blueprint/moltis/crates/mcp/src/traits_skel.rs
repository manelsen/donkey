//! Trait abstractions for MCP transport and client layers.
//!
//! These traits allow swapping the underlying MCP implementation (e.g. stdio vs rmcp-sdk)
//! without changing call sites in `manager.rs`, `tool_bridge.rs`, or `mcp_service.rs`.

use {async_trait::async_trait, serde_json::Value};

use crate::{
    client::McpClientState,
    error::Result,
    types::{JsonRpcResponse, McpToolDef, ToolsCallResult},
};

/// Transport layer for MCP communication (JSON-RPC).
///
/// `StdioTransport` implements this over stdin/stdout of a child process.
/// A future HTTP/SSE transport (e.g. via rmcp-sdk) would also implement this trait.
#[async_trait]
pub trait McpTransport: Send + Sync {
    /// Send a JSON-RPC request and wait for the response.
    async fn request(&self, method: &str, params: Option<Value>) -> Result<JsonRpcResponse>;

    /// Send a JSON-RPC notification (no response expected).
    async fn notify(&self, method: &str, params: Option<Value>) -> Result<()>;

    /// Check if the underlying connection/process is still alive.
    async fn is_alive(&self) -> bool;

    /// Kill/close the underlying connection/process.
    async fn kill(&self);
}

/// Client-level abstraction for an MCP server connection.
///
/// `McpClient` implements this over `StdioTransport`. A future `RmcpClient`
/// wrapper would also implement this trait.
#[async_trait]
pub trait McpClientTrait: Send + Sync {
    ...
}
