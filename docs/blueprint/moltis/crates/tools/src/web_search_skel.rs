use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use {
    async_trait::async_trait,
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
    tracing::{debug, warn},
};

use crate::error::Error;

use {
    moltis_agents::tool_registry::AgentTool,
    moltis_config::schema::{SearchProvider as ConfigSearchProvider, WebSearchConfig},
};

use crate::exec::EnvVarProvider;

/// Cached search result with expiry.
struct CacheEntry {
    ...
}

/// Web search tool — lets the LLM search the web via Brave Search or Perplexity.
///
/// When the configured provider's API key is missing and fallback is enabled,
/// the tool falls back to DuckDuckGo HTML search.
pub struct WebSearchTool {
    ...
}

#[derive(Debug, Clone)]
enum SearchProvider {
    ...
}

fn env_value_with_overrides(env_overrides: &HashMap<String, String>, key: &str) -> Option<String> {
    ...
}

/// A single Brave search result.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct BraveResult {
    ...
}

/// Perplexity (OpenAI-compatible) chat completion response (subset).
#[derive(Debug, Deserialize)]
struct PerplexityResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct PerplexityChoice {
    ...
}

#[derive(Debug, Deserialize)]
struct PerplexityMessage {
    ...
}

impl WebSearchTool {
    /// Build from config; returns `None` if disabled or no API key available.
    pub fn from_config(config: &WebSearchConfig) -> Option<Self> {

    /// Build from config, with optional env overrides used as fallback after
    /// process env. This avoids process-global env mutation in callers.
    pub fn from_config_with_env_overrides(
        config: &WebSearchConfig,
        env_overrides: &HashMap<String, String>,
    ) -> Option<Self> {
    ...
}

    fn new(
        provider: SearchProvider,
        configured_api_key: Secret<String>,
        max_results: u8,
        timeout: Duration,
        cache_ttl: Duration,
        fallback_enabled: bool,
    ) -> Self {
    ...
}

    /// Attach a runtime environment provider (credential store).
    pub fn with_env_provider(mut self, provider: Arc<dyn EnvVarProvider>) -> Self {
    ...
}

    async fn runtime_env_values(&self) -> HashMap<String, String> {
    ...
}

    fn lookup_env_value(env_values: &HashMap<String, String>, key: &str) -> Option<String> {
    ...
}

    fn api_key_candidates(&self) -> &'static [&'static str] {
    ...
}

    #[cfg(test)]
    async fn env_value_with_provider(&self, key: &str) -> Option<String> {
    ...
}

    async fn current_api_key(&self) -> String {
    ...
}

    fn cache_get(&self, key: &str) -> Option<serde_json::Value> {
    ...
}

    fn cache_set(&self, key: String, value: serde_json::Value) {
    ...
}

    async fn search_brave(
        &self,
        query: &str,
        count: u8,
        params: &serde_json::Value,
        accept_language: Option<&str>,
        api_key: &str,
    ) -> crate::Result<serde_json::Value> {
    ...
}

    async fn search_perplexity(
        &self,
        query: &str,
        api_key: &str,
        base_url: &str,
        model: &str,
    ) -> crate::Result<serde_json::Value> {
    ...
}

    /// Check whether DuckDuckGo is temporarily blocked due to a prior CAPTCHA.
    fn is_ddg_blocked(&self) -> bool {
    ...
}

    /// Block DuckDuckGo for `duration` after a CAPTCHA response.
    fn block_ddg(&self, duration: Duration) {
    ...
}

    /// Fallback: search DuckDuckGo's HTML endpoint when no API key is configured.
    async fn search_duckduckgo(&self, query: &str, count: u8) -> crate::Result<serde_json::Value> {
    ...
}
}

fn resolve_perplexity_base_url(base_url_override: Option<&str>, api_key: &str) -> String {
    ...
}

// ---------------------------------------------------------------------------
// DuckDuckGo HTML parsing helpers
// ---------------------------------------------------------------------------

/// Parse Brave JSON response into normalized result rows.
fn parse_brave_results(body: &serde_json::Value) -> Vec<BraveResult> {
    ...
}

/// Parse DuckDuckGo HTML search results into structured result objects.
fn parse_duckduckgo_html(html: &str, max_results: u8) -> Vec<serde_json::Value> {
    ...
}

/// Find the `href="..."` attribute value in the tag surrounding `class_pos`.
fn extract_href_before(html: &str, class_pos: usize) -> Option<String> {
    ...
}

/// Extract text content from the element at `class_pos` (after the closing `>`).
fn extract_tag_text(html: &str, class_pos: usize) -> String {
    ...
}

/// Strip HTML tags, keeping only text content.
fn strip_tags(s: &str) -> String {
    ...
}

/// Decode common HTML entities.
fn decode_html_entities(s: &str) -> String {
    ...
}

/// Resolve a DuckDuckGo redirect URL (`//duckduckgo.com/l/?uddg=...`) to the
/// actual destination. Returns the href as-is when it's not a redirect.
fn resolve_ddg_redirect(href: &str) -> String {
    ...
}

/// URL-encode helper (subset; reqwest doesn't re-export this).
mod urlencoding {
}

#[async_trait]
impl AgentTool for WebSearchTool {
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
