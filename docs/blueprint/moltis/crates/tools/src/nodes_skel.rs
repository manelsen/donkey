//! Agent-callable tools for querying and selecting remote nodes.
//!
//! Provides `nodes_list`, `nodes_describe`, and `nodes_select` tools that let
//! the agent programmatically interact with connected device nodes.

use std::sync::Arc;

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
};

use moltis_agents::tool_registry::AgentTool;

// ── Domain types ────────────────────────────────────────────────────────────

/// Serializable summary of a connected node, returned by the list/describe tools.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NodeInfo {
    ...
}

/// A provider discovered on a remote node (e.g. ollama, openai env key).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeProviderInfo {
    ...
}

// ── Provider trait ──────────────────────────────────────────────────────────

/// Abstraction that the gateway implements to supply node data to the tools
/// crate without a direct dependency.
///
/// Follows the same pattern as [`crate::exec::NodeExecProvider`].
#[async_trait]
pub trait NodeInfoProvider: Send + Sync {
    /// List all currently connected nodes.
    async fn list_nodes(&self) -> Vec<NodeInfo>;

    /// Describe a single node by id or display name.
    async fn describe_node(&self, node_ref: &str) -> Option<NodeInfo>;

    /// Assign (or clear) a node for a chat session.
    /// `node_ref` is an id or display name; `None` clears the assignment.
    async fn set_session_node(
        &self,
        session_key: &str,
        node_ref: Option<&str>,
    ) -> anyhow::Result<Option<String>>;

    /// Resolve a node reference (id or display name) to a canonical node_id.
    async fn resolve_node_id(&self, node_ref: &str) -> Option<String>;
}

// ── NodesListTool ───────────────────────────────────────────────────────────

pub struct NodesListTool {
    ...
}

impl NodesListTool {
    pub fn new(provider: Arc<dyn NodeInfoProvider>) -> Self {
}

#[async_trait]
impl AgentTool for NodesListTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, _params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

// ── NodesDescribeTool ───────────────────────────────────────────────────────

pub struct NodesDescribeTool {
    ...
}

impl NodesDescribeTool {
    pub fn new(provider: Arc<dyn NodeInfoProvider>) -> Self {
}

#[async_trait]
impl AgentTool for NodesDescribeTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

// ── NodesSelectTool ─────────────────────────────────────────────────────────

pub struct NodesSelectTool {
    ...
}

impl NodesSelectTool {
    pub fn new(provider: Arc<dyn NodeInfoProvider>) -> Self {
}

#[async_trait]
impl AgentTool for NodesSelectTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

#[cfg(test)]
mod tests {

    impl MockNodeInfoProvider {
        fn new(nodes: Vec<NodeInfo>) -> Self {

        fn sample_node(id: &str, name: Option<&str>, platform: &str) -> NodeInfo {
    ...
}
    }

    #[async_trait]
    impl NodeInfoProvider for MockNodeInfoProvider {
        async fn list_nodes(&self) -> Vec<NodeInfo> {

        async fn describe_node(&self, node_ref: &str) -> Option<NodeInfo> {
    ...
}

        async fn set_session_node(
            &self,
            _session_key: &str,
            node_ref: Option<&str>,
        ) -> anyhow::Result<Option<String>> {
    ...
}

        async fn resolve_node_id(&self, node_ref: &str) -> Option<String> {
    ...
}
    }

    fn two_nodes() -> Vec<NodeInfo> {
    ...
}

    // ── Tool schema tests ───────────────────────────────────────────────────

    #[test]
    fn tool_schemas_valid() {
    ...
}

    // ── List tool tests ─────────────────────────────────────────────────────

    #[tokio::test]
    async fn nodes_list_returns_all_connected() {
    ...
}

    #[tokio::test]
    async fn nodes_list_empty() {
    ...
}

    // ── Describe tool tests ─────────────────────────────────────────────────

    #[tokio::test]
    async fn nodes_describe_by_id() {
    ...
}

    #[tokio::test]
    async fn nodes_describe_by_name() {
    ...
}

    #[tokio::test]
    async fn nodes_describe_not_found() {
    ...
}

    // ── Select tool tests ───────────────────────────────────────────────────

    #[tokio::test]
    async fn nodes_select_assigns_node() {
    ...
}

    #[tokio::test]
    async fn nodes_select_clear_assignment() {
    ...
}

    #[tokio::test]
    async fn nodes_select_missing_session_key() {
    ...
}
}
