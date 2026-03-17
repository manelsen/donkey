//! Live MCP service implementation backed by `McpManager`.

use std::{collections::HashMap, sync::Arc};

use {
    anyhow::Result,
    async_trait::async_trait,
    secrecy::{ExposeSecret, Secret},
    serde_json::Value,
    tokio::sync::RwLock,
    tracing::{info, warn},
};

use {
    moltis_agents::tool_registry::{AgentTool, ToolRegistry},
    moltis_mcp::tool_bridge::{McpAgentTool, McpToolBridge},
};

use crate::services::{McpService, ServiceError, ServiceResult};

// ── McpToolAdapter: bridge McpAgentTool → AgentTool ─────────────────────────

/// Thin adapter that implements `AgentTool` (agents crate) by delegating to
/// `McpToolBridge` which implements `McpAgentTool` (mcp crate).
struct McpToolAdapter(McpToolBridge);

#[async_trait]
impl AgentTool for McpToolAdapter {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> Result<Value> {
    ...
}
}

// ── Sync helper ─────────────────────────────────────────────────────────────

/// Synchronize MCP tool bridges into the shared `ToolRegistry`.
///
/// Removes all existing `mcp__*` tools and re-registers current bridges.
pub async fn sync_mcp_tools(
    manager: &moltis_mcp::McpManager,
    registry: &Arc<RwLock<ToolRegistry>>,
) {
    ...
}

// ── Config parsing helper ───────────────────────────────────────────────────

/// Extract an `McpServerConfig` from JSON params.
///
/// For updates, omitted fields inherit from `existing`.
fn parse_server_config(
    params: &Value,
    existing: Option<&moltis_mcp::McpServerConfig>,
) -> Result<moltis_mcp::McpServerConfig, ServiceError> {
    ...
}

fn parse_string_map(value: &Value) -> HashMap<String, String> {
    ...
}

fn parse_secret_string_map(value: &Value) -> HashMap<String, Secret<String>> {
    ...
}

// ── LiveMcpService ──────────────────────────────────────────────────────────

/// Live MCP service delegating to `McpManager`.
pub struct LiveMcpService {
    ...
}

impl LiveMcpService {
    pub fn new(
        manager: Arc<moltis_mcp::McpManager>,
        config_env_overrides: HashMap<String, String>,
        credential_store: Option<Arc<crate::auth::CredentialStore>>,
    ) -> Self {

    /// Store a reference to the shared tool registry so MCP mutations
    /// can automatically sync tools.
    pub async fn set_tool_registry(&self, registry: Arc<RwLock<ToolRegistry>>) {
    ...
}

    /// Sync MCP tools into the shared tool registry (if set).
    pub async fn sync_tools_if_ready(&self) {
    ...
}

    /// Access the underlying manager.
    pub fn manager(&self) -> &Arc<moltis_mcp::McpManager> {
    ...
}

    pub async fn set_credential_store(&self, credential_store: Arc<crate::auth::CredentialStore>) {
    ...
}

    async fn refresh_manager_env_overrides(&self) {
    ...
}
}

fn merge_env_overrides(
    base_overrides: &HashMap<String, String>,
    additional: Vec<(String, String)>,
) -> HashMap<String, String> {
    ...
}

#[async_trait]
impl McpService for LiveMcpService {
    async fn list(&self) -> ServiceResult {

    async fn add(&self, params: Value) -> ServiceResult {
    ...
}

    async fn remove(&self, params: Value) -> ServiceResult {
    ...
}

    async fn enable(&self, params: Value) -> ServiceResult {
    ...
}

    async fn disable(&self, params: Value) -> ServiceResult {
    ...
}

    async fn status(&self, params: Value) -> ServiceResult {
    ...
}

    async fn tools(&self, params: Value) -> ServiceResult {
    ...
}

    async fn restart(&self, params: Value) -> ServiceResult {
    ...
}

    async fn update(&self, params: Value) -> ServiceResult {
    ...
}

    async fn reauth(&self, params: Value) -> ServiceResult {
    ...
}

    async fn oauth_start(&self, params: Value) -> ServiceResult {
    ...
}

    async fn oauth_complete(&self, params: Value) -> ServiceResult {
    ...
}
}

#[cfg(test)]
mod tests {

    #[test]
    fn parse_server_config_allows_sse_without_command() {
    ...
}

    #[test]
    fn parse_server_config_requires_command_for_stdio() {
    ...
}

    #[test]
    fn parse_server_config_requires_url_for_sse() {
    ...
}

    #[test]
    fn parse_server_config_update_preserves_existing_sse_fields() {
    ...
}

    #[test]
    fn parse_server_config_update_preserves_oauth_when_omitted() {
    ...
}

    #[test]
    fn parse_server_config_preserves_and_replaces_sse_headers() {
    ...
}

    #[test]
    fn parse_server_config_allows_clearing_sse_headers() {
    ...
}

    #[test]
    fn merge_env_overrides_keeps_config_values_authoritative() {
    ...
}

    #[tokio::test]
    async fn test_sync_mcp_tools_empty_manager() {
    ...
}

    #[tokio::test]
    async fn test_sync_mcp_tools_removes_stale_tools() {
    ...
}

    #[tokio::test]
    async fn test_sync_preserves_non_mcp_tools() {
    ...
}

    /// Minimal AgentTool implementation for testing.
    struct FakeTool(String);

    #[async_trait]
    impl AgentTool for FakeTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> Value {
    ...
}

        async fn execute(&self, _params: Value) -> Result<Value> {
    ...
}
    }
}
