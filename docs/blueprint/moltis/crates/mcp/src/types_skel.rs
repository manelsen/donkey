//! MCP protocol types (JSON-RPC 2.0 over stdio).

use std::error::Error as StdError;

use serde::{Deserialize, Serialize};

// ── JSON-RPC 2.0 ────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcRequest {
    ...
}

impl JsonRpcRequest {
    pub fn new(id: u64, method: &str, params: Option<serde_json::Value>) -> Self {
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcResponse {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcError {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcNotification {
    ...
}

// ── MCP Protocol Types ──────────────────────────────────────────────

/// Client capabilities sent during initialize.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ClientCapabilities {
    ...
}

/// Parameters for the `initialize` request.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientInfo {
    ...
}

/// Result from the `initialize` response.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResult {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ServerCapabilities {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ToolsCapability {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerInfo {
    ...
}

/// A tool exposed by an MCP server.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpToolDef {
    ...
}

/// Result from `tools/list`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolsListResult {
    ...
}

/// Parameters for `tools/call`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolsCallParams {
    ...
}

/// A content item returned from `tools/call`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ToolContent {
    ...
}

/// Result from `tools/call`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolsCallResult {
    ...
}

/// MCP protocol version we implement.
pub const PROTOCOL_VERSION: &str = "2024-11-05";

// ── Transport Errors ──────────────────────────────────────────────────

/// Typed manager errors for MCP lifecycle/auth flows.
#[derive(Debug, thiserror::Error)]
pub enum McpManagerError {
    ...
}

/// Typed transport errors for MCP SSE connections.
///
/// Used by `SseTransport` to distinguish recoverable auth errors (401)
/// from other HTTP failures, enabling the auth retry flow.
#[derive(Debug, thiserror::Error)]
pub enum McpTransportError {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_jsonrpc_response_with_result() {
    ...
}

    #[test]
    fn test_jsonrpc_response_with_error() {
    ...
}

    #[test]
    fn test_mcp_tool_def_deserialization() {
    ...
}

    #[test]
    fn test_tools_call_result_deserialization() {
    ...
}

    #[test]
    fn test_initialize_params_serialization() {
    ...
}
}
