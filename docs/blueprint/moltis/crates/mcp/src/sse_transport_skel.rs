//! HTTP/SSE transport for remote MCP servers (Streamable HTTP transport).
//!
//! Uses HTTP POST for JSON-RPC requests and GET for server-initiated SSE events.
//! Supports optional OAuth Bearer token injection and automatic 401 retry.

use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

use {
    reqwest::{Client, header::HeaderMap},
    secrecy::{ExposeSecret, Secret},
    tokio::sync::RwLock,
    tracing::{debug, info, warn},
};

use crate::{
    auth::SharedAuthProvider,
    error::{Context, Error, Result},
    remote::{ResolvedRemoteConfig, sanitize_reqwest_error},
    traits::McpTransport,
    types::{
        JsonRpcNotification, JsonRpcRequest, JsonRpcResponse, McpTransportError, PROTOCOL_VERSION,
    },
};

const MCP_PROTOCOL_VERSION_HEADER: &str = "MCP-Protocol-Version";
const MCP_SESSION_ID_HEADER: &str = "Mcp-Session-Id";
const STREAMABLE_ACCEPT_HEADER: &str = "application/json, text/event-stream";

/// HTTP/SSE-based transport for a remote MCP server.
pub struct SseTransport {
    ...
}

impl SseTransport {
    /// Create a new SSE transport pointing at the given MCP server URL.
    pub fn new(url: &str) -> Result<Arc<Self>> {

    pub fn new_with_remote(remote: ResolvedRemoteConfig) -> Result<Arc<Self>> {
    ...
}

    /// Create a new SSE transport with an OAuth auth provider.
    pub fn with_auth(url: &str, auth: SharedAuthProvider) -> Result<Arc<Self>> {
    ...
}

    pub fn with_auth_remote(
        remote: ResolvedRemoteConfig,
        auth: SharedAuthProvider,
    ) -> Result<Arc<Self>> {
    ...
}

    /// Build a request builder with optional Bearer token.
    async fn build_post(&self) -> Result<reqwest::RequestBuilder> {
    ...
}

    async fn store_session_id_from_response(&self, response: &reqwest::Response) {
    ...
}

    fn apply_default_headers(&self, mut req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
    ...
}

    fn response_is_event_stream(resp: &reqwest::Response) -> bool {
    ...
}

    fn parse_event_stream_response(body: &str, method: &str) -> Result<JsonRpcResponse> {
    ...
}

    /// Send a POST request and handle 401 with auth retry.
    /// Returns the HTTP response or a typed `McpTransportError`.
    async fn send_with_auth_retry(
        &self,
        method: &str,
        body: &impl serde::Serialize,
    ) -> Result<reqwest::Response> {
    ...
}
}

#[async_trait::async_trait]
impl McpTransport for SseTransport {
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

    #[test]
    fn test_sse_transport_invalid_url_fails_creation() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_is_alive_unreachable() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_request_unreachable() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_kill() {
    ...
}

    #[test]
    fn test_sse_transport_with_auth_creation() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_401_without_auth_returns_unauthorized() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_200_no_auth() {
    ...
}

    fn remote_with_headers(
        url: &str,
        headers: &[(&str, &str)],
    ) -> crate::remote::ResolvedRemoteConfig {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_custom_headers_injected() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_bearer_header_injected() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_oauth_authorization_overrides_custom_header() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_propagates_session_id() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_401_with_session_replays_before_reauth() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_parses_event_stream_response() {
    ...
}

    #[tokio::test]
    async fn test_sse_transport_kill_sends_delete_with_session_id() {
    ...
}
}
