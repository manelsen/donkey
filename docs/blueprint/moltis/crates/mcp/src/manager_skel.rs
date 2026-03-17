//! McpManager: lifecycle management for multiple MCP server connections.

use std::{collections::HashMap, sync::Arc};

use {
    secrecy::ExposeSecret,
    tokio::sync::RwLock,
    tracing::{info, warn},
};

use crate::{
    auth::{McpAuthState, McpOAuthOverride, McpOAuthProvider, SharedAuthProvider},
    client::{McpClient, McpClientState},
    error::{Context, Error, Result},
    registry::{McpOAuthConfig, McpRegistry, McpServerConfig, TransportType},
    remote::{ResolvedRemoteConfig, header_names, sanitize_url_for_display},
    tool_bridge::McpToolBridge,
    traits::McpClientTrait,
    types::{McpManagerError, McpToolDef, McpTransportError},
};

/// Status of a managed MCP server.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ServerStatus {
    ...
}

/// Mutable state behind the single `RwLock` on [`McpManager`].
pub struct McpManagerInner {
    ...
}

/// Manages the lifecycle of multiple MCP server connections.
pub struct McpManager {
    ...
}

impl McpManager {
    pub fn new(registry: McpRegistry) -> Self {

    pub fn new_with_env_overrides(
        registry: McpRegistry,
        env_overrides: HashMap<String, String>,
    ) -> Self {
    ...
}

    pub async fn set_env_overrides(&self, env_overrides: HashMap<String, String>) {
    ...
}

    fn build_auth_provider(
        name: &str,
        remote: &ResolvedRemoteConfig,
        oauth: Option<&McpOAuthConfig>,
    ) -> SharedAuthProvider {
    ...
}

    fn should_attempt_auth_connection(
        has_existing_auth_provider: bool,
        has_oauth_override: bool,
        has_stored_token: bool,
    ) -> bool {
    ...
}

    /// Start all enabled servers from the registry.
    pub async fn start_enabled(&self) -> Vec<String> {
    ...
}

    /// Start a single server connection.
    ///
    /// For SSE servers: attempts unauthenticated first. On 401 Unauthorized,
    /// stores auth context and returns `McpManagerError::OAuthRequired`.
    pub async fn start_server(&self, name: &str, config: &McpServerConfig) -> Result<()> {
    ...
}

    /// Stop a server connection.
    pub async fn stop_server(&self, name: &str) {
    ...
}

    /// Restart a server.
    pub async fn restart_server(&self, name: &str) -> Result<()> {
    ...
}

    /// Start OAuth for an SSE server and return the browser authorization URL.
    pub async fn oauth_start_server(&self, name: &str, redirect_uri: &str) -> Result<String> {
    ...
}

    /// Complete an OAuth callback by matching state across MCP auth providers.
    ///
    /// Returns the server name whose OAuth flow was completed.
    pub async fn oauth_complete_callback(&self, state: &str, code: &str) -> Result<String> {
    ...
}

    /// Trigger re-authentication for an SSE server.
    pub async fn reauth_server(&self, name: &str, redirect_uri: &str) -> Result<String> {
    ...
}

    /// Get the status of all configured servers.
    pub async fn status_all(&self) -> Vec<ServerStatus> {
    ...
}

    /// Get the status of a single server.
    pub async fn status(&self, name: &str) -> Option<ServerStatus> {
    ...
}

    /// Get tool bridges for all running servers (for registration into ToolRegistry).
    pub async fn tool_bridges(&self) -> Vec<McpToolBridge> {
    ...
}

    /// Get tools for a specific server.
    pub async fn server_tools(&self, name: &str) -> Option<Vec<McpToolDef>> {
    ...
}

    // ── Registry operations ─────────────────────────────────────────

    /// Add a server to the registry and optionally start it.
    pub async fn add_server(
        &self,
        name: String,
        config: McpServerConfig,
        start: bool,
    ) -> Result<()> {
    ...
}

    /// Remove a server from the registry and stop it.
    pub async fn remove_server(&self, name: &str) -> Result<bool> {
    ...
}

    /// Enable a server and start it.
    pub async fn enable_server(&self, name: &str) -> Result<bool> {
    ...
}

    /// Disable a server and stop it.
    pub async fn disable_server(&self, name: &str) -> Result<bool> {
    ...
}

    /// Get a snapshot of the registry for serialization.
    pub async fn registry_snapshot(&self) -> McpRegistry {
    ...
}

    /// Update a server's configuration and restart it if running.
    pub async fn update_server(&self, name: &str, config: McpServerConfig) -> Result<()> {
    ...
}

    /// Shut down all servers.
    pub async fn shutdown_all(&self) {
    ...
}
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_manager_creation() {
    ...
}

    #[test]
    fn test_should_attempt_auth_connection_with_existing_provider() {
    ...
}

    #[test]
    fn test_should_attempt_auth_connection_with_oauth_override() {
    ...
}

    #[test]
    fn test_should_attempt_auth_connection_with_stored_token() {
    ...
}

    #[test]
    fn test_should_attempt_auth_connection_without_auth_signals() {
    ...
}

    #[tokio::test]
    async fn test_status_all_empty() {
    ...
}

    #[tokio::test]
    async fn test_tool_bridges_empty() {
    ...
}

    #[tokio::test]
    async fn test_status_shows_stopped_for_configured_but_not_started() {
    ...
}

    #[tokio::test]
    async fn test_status_sanitizes_remote_url_and_hides_remote_env_values() {
    ...
}

    #[tokio::test]
    async fn test_status_hides_pending_oauth_url() {
    ...
}

    #[tokio::test]
    async fn test_reauth_server_no_auth_provider() {
    ...
}

    #[tokio::test]
    async fn test_oauth_start_server_requires_sse_transport() {
    ...
}

    #[tokio::test]
    async fn test_oauth_complete_callback_unknown_state() {
    ...
}
}
