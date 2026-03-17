//! Bridge MCP tools to the `AgentTool` trait so they can be used in the agent loop.

use std::sync::Arc;

use async_trait::async_trait;

use crate::{
    error::{Error, Result},
    traits::McpClientTrait,
    types::{McpToolDef, ToolContent},
};

/// Recursively strip null values from nested objects and arrays.
///
/// Top-level null stripping is handled by the caller; this recurses into
/// values that are themselves objects or arrays.
fn strip_nulls_recursive(map: &mut serde_json::Map<String, serde_json::Value>) {
    ...
}

/// An `AgentTool` implementation that delegates to an MCP server via `McpClient`.
pub struct McpToolBridge {
    ...
}

impl McpToolBridge {
    /// Create a bridge for a single MCP tool.
    pub fn new(
        server_name: &str,
        tool_def: &McpToolDef,
        client: Arc<tokio::sync::RwLock<dyn McpClientTrait>>,
    ) -> Self {

    /// Create bridges for all tools from a client.
    pub fn from_client(
        server_name: &str,
        tools: &[McpToolDef],
        client: Arc<tokio::sync::RwLock<dyn McpClientTrait>>,
    ) -> Vec<Self> {
    ...
}

    pub fn prefixed_name(&self) -> &str {
    ...
}

    /// The name of the MCP server this tool belongs to.
    pub fn server_name(&self) -> &str {
    ...
}
}

/// Trait for agent-callable tools, matching `AgentTool` in moltis-agents.
///
/// We define our own copy here to avoid a circular dependency on moltis-agents.
/// The gateway wires `McpToolBridge` into the `ToolRegistry` via a thin adapter.
#[async_trait]
pub trait McpAgentTool: Send + Sync {
    fn name(&self) -> &str;
    fn description(&self) -> &str;
    fn parameters_schema(&self) -> serde_json::Value;
    async fn execute(&self, params: serde_json::Value) -> Result<serde_json::Value>;
}

#[async_trait]
impl McpAgentTool for McpToolBridge {
    ...
}

#[cfg(test)]
mod tests {

    /// Mock MCP client that records the arguments passed to `call_tool`.
    struct MockMcpClient {
    ...
}

    #[async_trait]
    impl McpClientTrait for MockMcpClient {
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

        async fn call_tool(
            &self,
            _name: &str,
            arguments: serde_json::Value,
        ) -> Result<ToolsCallResult> {
    ...
}

        async fn is_alive(&self) -> bool {
    ...
}

        async fn shutdown(&mut self) {
    ...
}

    #[test]
    fn test_prefixed_name_format() {
    ...
}

    #[test]
    fn test_double_underscore_separator() {
    ...
}

    #[tokio::test]
    async fn test_execute_strips_internal_metadata() {
    ...
}

    #[tokio::test]
    async fn test_execute_passes_non_object_params_unchanged() {
    ...
}

    #[tokio::test]
    async fn test_execute_strips_null_values() {
    ...
}

    #[tokio::test]
    async fn test_execute_strips_nulls_in_nested_objects() {
    ...
}
}
