//! Kimi Code provider.
//!
//! Authentication uses the Kimi device-flow OAuth (same as kimi-cli).
//! The API is OpenAI-compatible at `https://api.kimi.com/coding/v1`.

use std::pin::Pin;

use {
    async_trait::async_trait,
    futures::StreamExt,
    moltis_oauth::{OAuthTokens, TokenStore, kimi_headers},
    secrecy::{ExposeSecret, Secret},
    tokio_stream::Stream,
    tracing::{debug, trace, warn},
};

use {
    super::openai_compat::{
        SseLineResult, StreamingToolState, finalize_stream, parse_openai_compat_usage_from_payload,
        parse_tool_calls, process_openai_sse_line, to_openai_tools,
    },
    moltis_agents::model::{ChatMessage, CompletionResponse, LlmProvider, StreamEvent},
};

// ── Constants ────────────────────────────────────────────────────────────────

const KIMI_API_BASE: &str = "https://api.kimi.com/coding/v1";
const KIMI_AUTH_HOST: &str = "https://auth.kimi.com";
const KIMI_CLIENT_ID: &str = "17e5f671-d194-4dfb-9706-5516cb48c098";
const PROVIDER_NAME: &str = "kimi-code";

/// Refresh threshold: 5 minutes before expiry.
const REFRESH_THRESHOLD_SECS: u64 = 300;

// ── Provider ─────────────────────────────────────────────────────────────────

enum AuthMode {
    ...
}

pub struct KimiCodeProvider {
    ...
}

impl KimiCodeProvider {
    /// Build a provider that authenticates via Kimi OAuth tokens.
    pub fn new(model: String) -> Self {

    /// Build a provider that authenticates via API key.
    pub fn new_with_api_key(api_key: Secret<String>, model: String, base_url: String) -> Self {
    ...
}

    fn should_send_kimi_headers(&self) -> bool {
    ...
}

    async fn get_auth_token(&self) -> anyhow::Result<String> {
    ...
}

    /// Load tokens and refresh if needed (< 5 min remaining).
    async fn get_valid_oauth_token(&self) -> anyhow::Result<String> {
    ...
}
}

fn build_access_denied_hint(status: reqwest::StatusCode, body_text: &str) -> Option<String> {
    ...
}

/// Refresh the access token using the Kimi token endpoint.
pub async fn refresh_access_token(
    client: &reqwest::Client,
    refresh_token: &str,
) -> anyhow::Result<OAuthTokens> {
    ...
}

/// Check if we have stored tokens for Kimi Code.
pub fn has_stored_tokens() -> bool {
    ...
}

/// Known Kimi Code models.
pub const KIMI_CODE_MODELS: &[(&str, &str)] = &[
    ("kimi-for-coding", "Kimi For Coding"),
    ("kimi-k2.5", "Kimi K2.5"),
];

// ── LlmProvider impl ────────────────────────────────────────────────────────

#[async_trait]
impl LlmProvider for KimiCodeProvider {
    fn name(&self) -> &str {
    ...
}

    fn id(&self) -> &str {
    ...
}

    fn supports_tools(&self) -> bool {
    ...
}

    async fn complete(
        &self,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
    ) -> anyhow::Result<CompletionResponse> {
    ...
}

    #[allow(clippy::collapsible_if)]
    fn stream(
        &self,
        messages: Vec<ChatMessage>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

    #[allow(clippy::collapsible_if)]
    fn stream_with_tools(
        &self,
        messages: Vec<ChatMessage>,
        tools: Vec<serde_json::Value>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
