//! MCP client: manages the protocol handshake and tool interactions with a single MCP server.

use std::{collections::HashMap, sync::Arc};

use tracing::{debug, info, warn};

#[cfg(feature = "metrics")]
use std::time::Instant;

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, gauge, histogram, labels, mcp as mcp_metrics};

use crate::{
    auth::SharedAuthProvider,
    error::{Context, Error, Result},
    remote::ResolvedRemoteConfig,
    sse_transport::SseTransport,
    traits::{McpClientTrait, McpTransport},
    transport::StdioTransport,
    types::{
        ClientCapabilities, ClientInfo, InitializeParams, InitializeResult, McpToolDef,
        PROTOCOL_VERSION, ToolsCallParams, ToolsCallResult, ToolsListResult,
    },
};

/// State of an MCP client connection.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum McpClientState {
    ...
}

/// An MCP client connected to a single server via stdio.
pub struct McpClient {
    ...
}

impl McpClient {
    /// Spawn the server process and perform the MCP handshake (initialize + initialized).
    pub async fn connect(
        server_name: &str,
        command: &str,
        args: &[String],
        env: &HashMap<String, String>,
    ) -> Result<Self> {
        #[cfg(feature = "metrics")]

    /// Connect to a remote MCP server over HTTP/SSE.
    pub async fn connect_sse(server_name: &str, remote: &ResolvedRemoteConfig) -> Result<Self> {
    ...
}

    /// Connect to a remote MCP server over HTTP/SSE with an OAuth auth provider.
    pub async fn connect_sse_with_auth(
        server_name: &str,
        remote: &ResolvedRemoteConfig,
        auth: SharedAuthProvider,
    ) -> Result<Self> {
    ...
}

    async fn initialize(&mut self) -> Result<()> {
    ...
}

    fn ensure_ready(&self) -> Result<()> {
    ...
}
}

#[async_trait::async_trait]
impl McpClientTrait for McpClient {
    fn server_name(&self) -> &str {

    fn state(&self) -> McpClientState {
    ...
}

    fn tools(&self) -> &[McpToolDef] {
    ...
}

    async fn list_tools(&mut self) -> Result<&[McpToolDef]> {
    ...
}

    async fn call_tool(&self, name: &str, arguments: serde_json::Value) -> Result<ToolsCallResult> {
    ...
}

    async fn is_alive(&self) -> bool {
    ...
}

    async fn shutdown(&mut self) {
    ...
}
}

#[cfg(test)]
mod tests {
}
