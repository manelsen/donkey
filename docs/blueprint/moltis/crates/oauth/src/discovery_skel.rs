//! OAuth 2.1 metadata discovery for MCP servers.
//!
//! Implements:
//! - RFC 9728: OAuth 2.0 Protected Resource Metadata
//! - RFC 8414: OAuth 2.0 Authorization Server Metadata
//! - RFC 7591: OAuth 2.0 Dynamic Client Registration

use {
    reqwest::Client,
    serde::{Deserialize, Serialize},
    tracing::{debug, info},
    url::Url,
};

use crate::{Error, Result};

// ── Protected Resource Metadata (RFC 9728) ─────────────────────────────────

/// Metadata returned by `/.well-known/oauth-protected-resource`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProtectedResourceMetadata {
    ...
}

/// Fetch protected resource metadata from `{resource_url}/.well-known/oauth-protected-resource`.
pub async fn fetch_resource_metadata(
    client: &Client,
    resource_url: &Url,
) -> Result<ProtectedResourceMetadata> {
    ...
}

// ── Authorization Server Metadata (RFC 8414) ───────────────────────────────

/// Metadata returned by `/.well-known/oauth-authorization-server`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthorizationServerMetadata {
    ...
}

/// Fetch authorization server metadata from `{as_url}/.well-known/oauth-authorization-server`.
pub async fn fetch_as_metadata(
    client: &Client,
    as_url: &Url,
) -> Result<AuthorizationServerMetadata> {
    ...
}

// ── Dynamic Client Registration (RFC 7591) ─────────────────────────────────

/// Request body for dynamic client registration.
#[derive(Debug, Clone, Serialize)]
pub struct ClientRegistrationRequest {
    ...
}

/// Successful registration response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientRegistrationResponse {
    ...
}

/// Perform dynamic client registration at the given endpoint.
pub async fn register_client(
    client: &Client,
    registration_endpoint: &str,
    redirect_uris: Vec<String>,
    client_name: &str,
) -> Result<ClientRegistrationResponse> {
    ...
}

// ── WWW-Authenticate header parsing ────────────────────────────────────────

/// Parse the `resource_metadata` URL from a `WWW-Authenticate: Bearer ...` header.
///
/// Example header: `Bearer realm="example", resource_metadata="https://example.com/.well-known/oauth-protected-resource"`
#[must_use]
pub fn parse_www_authenticate(header: &str) -> Option<String> {
    ...
}

// ── Helpers ────────────────────────────────────────────────────────────────

/// Build a `/.well-known/<suffix>` URL following RFC 8615 path conventions.
fn build_well_known_url(base: &Url, suffix: &str) -> Result<Url> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn parse_www_authenticate_with_realm() {
    ...
}

    #[test]
    fn parse_www_authenticate_lowercase() {
    ...
}

    #[test]
    fn parse_www_authenticate_no_resource_metadata() {
    ...
}

    #[test]
    fn parse_www_authenticate_not_bearer() {
    ...
}

    #[test]
    fn parse_www_authenticate_empty() {
    ...
}

    #[test]
    fn parse_www_authenticate_with_space_around_equals() {
    ...
}

    // ── Well-known URL building ────────────────────────────────────────

    #[test]
    fn build_well_known_url_basic() {
    ...
}

    #[test]
    fn build_well_known_url_with_path() {
    ...
}

    #[test]
    fn build_well_known_url_with_trailing_slash() {
    ...
}

    // ── HTTP integration tests (with mockito) ──────────────────────────

    #[tokio::test]
    async fn fetch_resource_metadata_success() {
    ...
}

    #[tokio::test]
    async fn fetch_resource_metadata_not_found() {
    ...
}

    #[tokio::test]
    async fn fetch_as_metadata_success() {
    ...
}

    #[tokio::test]
    async fn fetch_as_metadata_malformed_json() {
    ...
}

    #[tokio::test]
    async fn register_client_success() {
    ...
}

    #[tokio::test]
    async fn register_client_no_secret() {
    ...
}

    #[tokio::test]
    async fn register_client_error_response() {
    ...
}

    #[tokio::test]
    async fn fetch_resource_metadata_network_failure() {
    ...
}
}
