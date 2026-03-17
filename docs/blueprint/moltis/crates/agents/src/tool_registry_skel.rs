use {
    anyhow::Result,
    async_trait::async_trait,
    std::{collections::HashMap, sync::Arc},
};

/// Agent-callable tool.
#[async_trait]
pub trait AgentTool: Send + Sync {
    fn name(&self) -> &str;
    fn description(&self) -> &str;
    fn parameters_schema(&self) -> serde_json::Value;
    /// Opportunistic post-start initialization hook.
    async fn warmup(&self) -> Result<()> {
    ...
}
    async fn execute(&self, params: serde_json::Value) -> Result<serde_json::Value>;
}

/// Where a tool originates from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ToolSource {
    ...
}

/// Internal entry pairing a tool with its source metadata.
struct ToolEntry {
    ...
}

/// Registry of available tools for an agent run.
///
/// Tools are stored as `Arc<dyn AgentTool>` so the registry can be cheaply
/// cloned (e.g. for sub-agents that need a filtered copy of the parent's tools).
pub struct ToolRegistry {
    ...
}

impl Default for ToolRegistry {
    fn default() -> Self {
}

impl ToolRegistry {
    pub fn new() -> Self {

    /// Register a built-in tool.
    pub fn register(&mut self, tool: Box<dyn AgentTool>) {
    ...
}

    /// Register a tool from an MCP server.
    pub fn register_mcp(&mut self, tool: Box<dyn AgentTool>, server: String) {
    ...
}

    /// Register a tool from a WASM component.
    pub fn register_wasm(&mut self, tool: Box<dyn AgentTool>, component_hash: [u8; 32]) {
    ...
}

    /// Replace an existing tool by name, preserving its source metadata.
    ///
    /// Returns `true` if an existing tool was replaced, `false` if this was a new entry.
    pub fn replace(&mut self, tool: Box<dyn AgentTool>) -> bool {
    ...
}

    pub fn unregister(&mut self, name: &str) -> bool {
    ...
}

    /// Remove all MCP-sourced tools. Returns the number of tools removed.
    pub fn unregister_mcp(&mut self) -> usize {
    ...
}

    pub fn get(&self, name: &str) -> Option<&dyn AgentTool> {
    ...
}

    /// Return a cloned tool handle by name.
    pub fn get_arc(&self, name: &str) -> Option<Arc<dyn AgentTool>> {
    ...
}

    pub fn list_schemas(&self) -> Vec<serde_json::Value> {
    ...
}

    /// List registered tool names.
    pub fn list_names(&self) -> Vec<String> {
    ...
}

    /// Clone the registry, excluding tools whose names start with `prefix`.
    pub fn clone_without_prefix(&self, prefix: &str) -> ToolRegistry {
    ...
}

    /// Clone the registry, excluding all MCP-sourced tools.
    pub fn clone_without_mcp(&self) -> ToolRegistry {
    ...
}

    /// Clone the registry, excluding tools whose names are in `exclude`.
    pub fn clone_without(&self, exclude: &[&str]) -> ToolRegistry {
    ...
}

    /// Clone the registry keeping only tools that match `predicate`.
    pub fn clone_allowed_by<F>(&self, mut predicate: F) -> ToolRegistry
    where
        F: FnMut(&str) -> bool,
    {
        let tools = self
            .tools
            .iter()
            .filter(|(name, _)| predicate(name))
            .map(|(name, entry)| {
                (name.clone(), ToolEntry {
                    tool: Arc::clone(&entry.tool),
                    source: entry.source.clone(),
                })
            })
            .collect();
        ToolRegistry { tools }
    }
}

fn hex_component_hash(component_hash: [u8; 32]) -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[async_trait]
    impl AgentTool for DummyTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, _params: serde_json::Value) -> Result<serde_json::Value> {
    ...
}
    }

    #[test]
    fn test_clone_without_prefix() {
    ...
}

    #[test]
    fn test_clone_without_prefix_no_match() {
    ...
}

    #[test]
    fn test_clone_without_mcp() {
    ...
}

    #[test]
    fn test_unregister_mcp() {
    ...
}

    #[test]
    fn test_list_schemas_includes_source() {
    ...
}

    #[test]
    fn test_list_names() {
    ...
}

    #[test]
    fn test_get_arc_returns_cloned_tool_handle() {
    ...
}

    #[test]
    fn test_clone_allowed_by() {
    ...
}
}
