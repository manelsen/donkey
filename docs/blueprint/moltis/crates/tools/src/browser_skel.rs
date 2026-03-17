//! Browser automation tool for LLM agents.
//!
//! This tool provides full browser automation capabilities including:
//! - Navigation with JavaScript execution
//! - Screenshots of pages
//! - DOM snapshots with numbered element references
//! - Clicking, typing, scrolling on elements
//! - JavaScript evaluation

use {
    crate::sandbox::SandboxRouter,
    async_trait::async_trait,
    moltis_agents::tool_registry::AgentTool,
    moltis_browser::{BrowserManager, BrowserRequest},
    std::{borrow::Cow, collections::HashMap, sync::Arc},
    tokio::sync::{OnceCell, RwLock},
    tracing::debug,
};

use crate::error::Error;

/// Browser automation tool for interacting with web pages.
///
/// Unlike `web_fetch` which just retrieves page content, this tool allows
/// full browser interaction: clicking buttons, filling forms, taking
/// screenshots, and executing JavaScript.
///
/// This tool automatically tracks and reuses browser session IDs. When
/// the LLM doesn't provide a session_id (or provides empty string), the
/// tool will reuse the most recently created browser session for the current
/// chat session. This prevents pool exhaustion without leaking browser state
/// across unrelated chats.
pub struct BrowserTool {
    ...
}

impl BrowserTool {
    const DEFAULT_SESSION_KEY: &'static str = "main";
    /// Maximum number of tracked browser sessions. When exceeded the oldest
    /// entry (by insertion order, approximated by picking an arbitrary key) is
    /// evicted to prevent unbounded memory growth from abandoned chats.
    const MAX_TRACKED_SESSIONS: usize = 128;

    /// Create a new browser tool from browser configuration.
    pub fn new(config: moltis_browser::BrowserConfig) -> Self {

    /// Attach a sandbox router for per-session sandbox mode resolution.
    pub fn with_sandbox_router(mut self, router: Arc<SandboxRouter>) -> Self {
    ...
}

    /// Create from config; returns `None` if browser is disabled.
    pub fn from_config(config: &moltis_config::schema::BrowserConfig) -> Option<Self> {
    ...
}

    fn cache_key(session_key: Option<&str>) -> Cow<'static, str> {
    ...
}

    /// Clear the tracked browser session for the current chat/session context
    /// (e.g., after explicit close).
    async fn clear_session(&self, session_key: &str) {
    ...
}

    /// Save the browser session ID for future reuse in the same chat/session
    /// context.
    async fn save_session(&self, session_key: &str, session_id: &str) {
    ...
}

    /// Get the tracked browser session ID for the current chat/session
    /// context, if available.
    async fn get_saved_session(&self, session_key: &str) -> Option<String> {
    ...
}

    async fn manager(&self) -> Arc<BrowserManager> {
    ...
}
}

#[async_trait]
impl AgentTool for BrowserTool {
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

    async fn warmup(&self) -> anyhow::Result<()> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_disabled_returns_none() {
    ...
}

    #[test]
    fn test_parameters_schema_has_required_action() {
    ...
}

    #[tokio::test]
    async fn saved_browser_sessions_are_scoped_by_chat_session() {
    ...
}

    #[tokio::test]
    async fn empty_session_id_is_not_saved() {
    ...
}

    #[tokio::test]
    async fn session_cache_evicts_when_full() {
    ...
}

    #[tokio::test]
    async fn clearing_one_chat_session_keeps_other_browser_sessions() {
    ...
}
}
