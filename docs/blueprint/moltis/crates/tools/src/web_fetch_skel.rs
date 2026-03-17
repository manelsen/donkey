use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

use {async_trait::async_trait, tracing::debug, url::Url};

use crate::error::Error;

use {
    crate::ssrf::ssrf_check, moltis_agents::tool_registry::AgentTool,
    moltis_config::schema::WebFetchConfig,
};

/// Cached fetch result with expiry.
struct CacheEntry {
    ...
}

/// Web fetch tool — lets the LLM fetch a URL and extract readable content.
pub struct WebFetchTool {
    ...
}

impl WebFetchTool {
    /// Build from config; returns `None` if disabled.
    pub fn from_config(config: &WebFetchConfig) -> Option<Self> {

    /// Route HTTP traffic through a proxy (e.g. the trusted-network proxy).
    #[must_use]
    pub fn with_proxy(mut self, url: String) -> Self {
    ...
}

    fn cache_get(&self, key: &str) -> Option<serde_json::Value> {
    ...
}

    fn cache_set(&self, key: String, value: serde_json::Value) {
    ...
}

    async fn fetch_url(
        &self,
        url_str: &str,
        extract_mode: &str,
        max_chars: usize,
        accept_language: Option<&str>,
    ) -> crate::Result<serde_json::Value> {
    ...
}
}

/// Extract readable content from the response body based on content type.
fn extract_content(
    body: &str,
    content_type: &str,
    requested_mode: &str,
    use_readability: bool,
) -> (String, String) {
    ...
}

/// Simple HTML to text conversion: strip tags, decode basic entities,
/// collapse whitespace. A lightweight alternative to a full readability
/// crate — good enough for most pages.
fn html_to_text(html: &str) -> String {
    ...
}

/// Truncate a string at a char boundary, not mid-UTF-8.
fn truncate_at_char_boundary(s: &str, max: usize) -> String {
    ...
}

#[async_trait]
impl AgentTool for WebFetchTool {
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

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn default_tool() -> WebFetchTool {
    ...
}

    #[test]
    fn test_tool_name_and_schema() {
    ...
}

    #[tokio::test]
    async fn test_missing_url_param() {
    ...
}

    // --- SSRF tests ---

    use rstest::rstest;

    #[rstest]
    #[case("127.0.0.1", true)]
    #[case("192.168.1.1", true)]
    #[case("10.0.0.1", true)]
    #[case("172.16.0.1", true)]
    #[case("169.254.1.1", true)]
    #[case("0.0.0.0", true)]
    #[case("8.8.8.8", false)]
    #[case("1.1.1.1", false)]
    fn test_is_private_ip_v4(#[case] addr: &str, #[case] expected: bool) {
    ...
}

    #[rstest]
    #[case("::1", true)]
    #[case("::", true)]
    #[case("fd00::1", true)]
    #[case("fe80::1", true)]
    #[case("2607:f8b0:4004:800::200e", false)]
    fn test_is_private_ip_v6(#[case] addr: &str, #[case] expected: bool) {
    ...
}

    #[tokio::test]
    async fn test_ssrf_blocks_localhost_url() {
    ...
}

    #[tokio::test]
    async fn test_ssrf_blocks_private_ip() {
    ...
}

    #[tokio::test]
    async fn test_ssrf_blocks_link_local() {
    ...
}

    // --- Content extraction tests ---

    #[test]
    fn test_html_to_text_basic() {
    ...
}

    #[test]
    fn test_html_to_text_strips_scripts() {
    ...
}

    #[test]
    fn test_html_to_text_strips_styles() {
    ...
}

    #[test]
    fn test_html_to_text_entities() {
    ...
}

    #[test]
    fn test_extract_content_json() {
    ...
}

    #[test]
    fn test_extract_content_plain_text() {
    ...
}

    #[test]
    fn test_truncation() {
    ...
}

    #[test]
    fn test_truncation_utf8_boundary() {
    ...
}

    // --- Cache tests ---

    #[test]
    fn test_cache_hit_and_miss() {
    ...
}

    #[test]
    fn test_cache_disabled_zero_ttl() {
    ...
}

    // --- Config tests ---

    #[test]
    fn test_from_config_disabled() {
    ...
}

    #[test]
    fn test_from_config_enabled() {
    ...
}

    #[tokio::test]
    async fn test_unsupported_scheme() {
    ...
}

    // --- SSRF allowlist tests ---

    #[test]
    fn test_is_ssrf_allowed_matching_cidr() {
    ...
}

    #[test]
    fn test_is_ssrf_allowed_non_matching() {
    ...
}

    #[test]
    fn test_is_ssrf_allowed_empty_blocks_all() {
    ...
}

    #[test]
    fn test_is_ssrf_allowed_single_host() {
    ...
}

    #[test]
    fn test_is_ssrf_allowed_ipv6() {
    ...
}

    #[tokio::test]
    async fn test_ssrf_check_allowlist_permits_private_ip() {
    ...
}

    #[tokio::test]
    async fn test_ssrf_check_allowlist_still_blocks_non_matching() {
    ...
}

    #[test]
    fn test_from_config_parses_ssrf_allowlist() {
    ...
}

    #[test]
    fn test_with_proxy() {
    ...
}

    #[test]
    fn test_from_config_has_no_proxy_by_default() {
    ...
}
}
