//! OAuth 2.1 authentication provider for MCP servers.
//!
//! Implements the MCP Authorization Spec (2025-06-18):
//! - Protected resource metadata discovery (RFC 9728)
//! - Authorization server metadata discovery (RFC 8414)
//! - Dynamic client registration (RFC 7591)
//! - PKCE authorization code flow (web UI callback driven)

use std::sync::Arc;

use {
    async_trait::async_trait,
    secrecy::{ExposeSecret, Secret},
    tokio::sync::RwLock,
    tracing::{debug, info, warn},
    url::Url,
};

use crate::{
    error::{Context, Error, Result},
    remote::sanitize_url_for_display,
};

use moltis_oauth::{
    OAuthConfig, OAuthFlow, OAuthTokens, RegistrationStore, StoredRegistration, TokenStore,
    fetch_as_metadata, fetch_resource_metadata, parse_www_authenticate, register_client,
};

// ── Auth state ─────────────────────────────────────────────────────────────

/// Observable state of MCP OAuth authentication.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum McpAuthState {
    ...
}

// ── Auth provider trait ────────────────────────────────────────────────────

/// Provides OAuth tokens for authenticating MCP HTTP requests.
#[async_trait]
pub trait McpAuthProvider: Send + Sync {
    /// Return a valid access token, refreshing if necessary.
    /// Returns `None` if no token is available and auth hasn't been initiated.
    async fn access_token(&self) -> Result<Option<Secret<String>>>;

    /// Handle a 401 Unauthorized response by performing the OAuth flow.
    /// Returns `true` if authentication succeeded and the request should be retried.
    async fn handle_unauthorized(&self, www_authenticate: Option<&str>) -> Result<bool>;

    /// Start an OAuth flow using the provided redirect URI and return an auth URL.
    async fn start_oauth(
        &self,
        redirect_uri: &str,
        www_authenticate: Option<&str>,
    ) -> Result<Option<String>>;

    /// Complete a pending OAuth flow for this provider.
    ///
    /// Returns `true` when `state` matched and completion was attempted.
    async fn complete_oauth(&self, state: &str, code: &str) -> Result<bool>;

    /// Pending OAuth authorization URL for this provider, if any.
    fn pending_auth_url(&self) -> Option<String>;

    /// Current authentication state.
    fn auth_state(&self) -> McpAuthState;
}

// ── Concrete OAuth provider ────────────────────────────────────────────────

/// Manual OAuth override configuration (from `moltis.toml`).
#[derive(Debug, Clone)]
pub struct McpOAuthOverride {
    ...
}

/// OAuth 2.1 provider for a single MCP server.
pub struct McpOAuthProvider {
    ...
}

#[derive(Debug, Clone)]
struct PendingOAuthFlow {
    ...
}

impl McpOAuthProvider {
    pub fn new(server_name: &str, server_url: &str) -> Self {

    /// Create with custom stores (for testing).
    pub fn with_stores(
        server_name: &str,
        server_url: &str,
        token_store: TokenStore,
        registration_store: RegistrationStore,
    ) -> Self {
    ...
}

    /// Set a manual OAuth override (skip discovery + dynamic registration).
    pub fn with_oauth_override(mut self, ov: McpOAuthOverride) -> Self {
    ...
}

    /// Token store key for this server.
    fn store_key(&self) -> String {
    ...
}

    /// Check whether the cached token is expired or near-expiry (60s buffer).
    fn is_token_expired(tokens: &OAuthTokens) -> bool {
    ...
}

    /// Try to refresh tokens using the refresh token.
    async fn try_refresh(&self, tokens: &OAuthTokens) -> Result<Option<OAuthTokens>> {
    ...
}

    async fn start_web_oauth_flow(
        &self,
        redirect_uri: &str,
        www_authenticate: Option<&str>,
    ) -> Result<String> {
    ...
}

    async fn complete_web_oauth_flow(&self, state: &str, code: &str) -> Result<bool> {
    ...
}

    /// Extract the origin (scheme + host + port) from a URL, stripping the path.
    fn origin_url(url: &Url) -> Url {
    ...
}

    /// Build an RFC 8707 resource indicator from a server URL origin.
    ///
    /// Uses scheme + host (+ explicit port) without path/query/fragment.
    fn origin_resource(url: &Url) -> String {
    ...
}

    /// Discover resource + AS metadata and perform dynamic client registration.
    ///
    /// Returns `(client_id, auth_url, token_url, scopes, resource)`.
    ///
    /// Per the MCP Authorization spec, well-known metadata URLs are tried at the
    /// server's full URL first (path-aware), then at the origin (scheme + host)
    /// as a fallback.
    async fn discover_and_register(
        &self,
        www_authenticate: Option<&str>,
        redirect_uri: &str,
    ) -> Result<(String, String, String, Vec<String>, String)> {
    ...
}
}

#[async_trait]
impl McpAuthProvider for McpOAuthProvider {
    async fn access_token(&self) -> Result<Option<Secret<String>>> {
            #[allow(clippy::collapsible_if)]

    async fn handle_unauthorized(&self, www_authenticate: Option<&str>) -> Result<bool> {
    ...
}

    async fn start_oauth(
        &self,
        redirect_uri: &str,
        www_authenticate: Option<&str>,
    ) -> Result<Option<String>> {
    ...
}

    async fn complete_oauth(&self, state: &str, code: &str) -> Result<bool> {
    ...
}

    fn pending_auth_url(&self) -> Option<String> {
    ...
}

    fn auth_state(&self) -> McpAuthState {
    ...
}
}

/// A no-op auth provider for servers that don't need authentication.
pub struct NoAuthProvider;

#[async_trait]
impl McpAuthProvider for NoAuthProvider {
    async fn access_token(&self) -> Result<Option<Secret<String>>> {

    async fn handle_unauthorized(&self, _www_authenticate: Option<&str>) -> Result<bool> {
    ...
}

    async fn start_oauth(
        &self,
        _redirect_uri: &str,
        _www_authenticate: Option<&str>,
    ) -> Result<Option<String>> {
    ...
}

    async fn complete_oauth(&self, _state: &str, _code: &str) -> Result<bool> {
    ...
}

    fn pending_auth_url(&self) -> Option<String> {
    ...
}

    fn auth_state(&self) -> McpAuthState {
    ...
}
}

// ── Thread-safe wrapper ────────────────────────────────────────────────────

/// Type alias for a shared auth provider.
pub type SharedAuthProvider = Arc<dyn McpAuthProvider>;

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn origin_url_preserves_port() {
    ...
}

    #[test]
    fn origin_url_root_unchanged() {
    ...
}

    #[test]
    fn origin_url_strips_query_and_fragment() {
    ...
}

    #[test]
    fn origin_resource_strips_path_and_trailing_slash() {
    ...
}

    #[test]
    fn origin_resource_preserves_explicit_port() {
    ...
}

    #[test]
    fn auth_state_serialization() {
    ...
}

    #[tokio::test]
    async fn no_auth_provider_returns_none() {
    ...
}

    #[test]
    fn token_expiry_check() {
    ...
}

    #[tokio::test]
    async fn provider_loads_from_store() {
    ...
}

    #[tokio::test]
    async fn provider_returns_none_for_empty_store() {
    ...
}

    #[tokio::test]
    async fn provider_returns_none_for_expired_token_no_refresh() {
    ...
}

    #[tokio::test]
    async fn discovery_falls_back_to_origin_as_metadata_for_path_url() {
    ...
}

    #[tokio::test]
    async fn dynamic_registration_uses_exact_redirect_uri() {
    ...
}

    #[test]
    fn store_key_format() {
    ...
}
}
