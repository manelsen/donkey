//! GitHub Copilot provider.
//!
//! Authentication uses the GitHub device-flow OAuth to obtain a GitHub token,
//! then exchanges it for a short-lived Copilot API token via
//! `https://api.github.com/copilot_internal/v2/token`.
//!
//! The Copilot API itself is OpenAI-compatible (`/chat/completions`).

use std::{collections::HashSet, pin::Pin, sync::mpsc, time::Duration};

use {
    async_trait::async_trait,
    futures::StreamExt,
    moltis_oauth::{OAuthTokens, TokenStore},
    secrecy::{ExposeSecret, Secret},
    tokio_stream::Stream,
    tracing::{debug, trace, warn},
};

use {
    super::openai_compat::{
        ResponsesStreamState, SseLineResult, StreamingToolState, finalize_responses_stream,
        finalize_stream, parse_openai_compat_usage_from_payload, parse_responses_completion,
        parse_tool_calls, process_openai_sse_line, process_responses_sse_line,
        split_responses_instructions_and_input, to_openai_tools, to_responses_api_tools,
    },
    moltis_agents::model::{ChatMessage, CompletionResponse, LlmProvider, StreamEvent},
};

// ── Constants ────────────────────────────────────────────────────────────────

/// GitHub OAuth app client ID for Copilot (VS Code's public client ID).
const GITHUB_CLIENT_ID: &str = "Iv1.b507a08c87ecfe98";

const GITHUB_DEVICE_CODE_URL: &str = "https://github.com/login/device/code";
const GITHUB_TOKEN_URL: &str = "https://github.com/login/oauth/access_token";
const COPILOT_TOKEN_URL: &str = "https://api.github.com/copilot_internal/v2/token";
const COPILOT_API_BASE: &str = "https://api.individual.githubcopilot.com";
const COPILOT_MODELS_ENDPOINT: &str = "https://api.individual.githubcopilot.com/models";

const PROVIDER_NAME: &str = "github-copilot";

/// Required headers for the Copilot chat completions API.
/// The API rejects requests without `Editor-Version`.
const EDITOR_VERSION: &str = "vscode/1.96.2";
const COPILOT_USER_AGENT: &str = "GitHubCopilotChat/0.26.7";

// ── Device flow types ────────────────────────────────────────────────────────

#[derive(Debug, serde::Deserialize)]
pub struct DeviceCodeResponse {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct GithubTokenResponse {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct CopilotTokenResponse {
    ...
}

// ── Provider ─────────────────────────────────────────────────────────────────

pub struct GitHubCopilotProvider {
    ...
}

impl GitHubCopilotProvider {
    pub fn new(model: String) -> Self {

    /// Start the GitHub device-flow: request a device code from GitHub.
    pub async fn request_device_code(
        client: &reqwest::Client,
    ) -> anyhow::Result<DeviceCodeResponse> {
    ...
}

    /// Poll GitHub for the access token after the user has entered the code.
    pub async fn poll_for_token(
        client: &reqwest::Client,
        device_code: &str,
        interval: u64,
    ) -> anyhow::Result<String> {
    ...
}

    /// Get a valid Copilot API token, exchanging the GitHub token if needed.
    async fn get_valid_copilot_token(&self) -> anyhow::Result<String> {
    ...
}
}

fn home_token_store_if_different() -> Option<TokenStore> {
    ...
}

fn token_store_with_provider_tokens(primary: &TokenStore) -> Option<TokenStore> {
    ...
}

/// Check if we have stored GitHub tokens for Copilot.
pub fn has_stored_tokens() -> bool {
    ...
}

/// Known Copilot models.
/// The list is intentionally broad; if a model isn't available for the user's
/// plan Copilot will return an error.
pub const COPILOT_MODELS: &[(&str, &str)] = &[
    ("gpt-4o", "GPT-4o (Copilot)"),
    ("gpt-4.1", "GPT-4.1 (Copilot)"),
    ("gpt-4.1-mini", "GPT-4.1 Mini (Copilot)"),
    ("gpt-4.1-nano", "GPT-4.1 Nano (Copilot)"),
    ("gpt-5.4", "GPT-5.4 (Copilot)"),
    ("gpt-5.4-pro", "GPT-5.4 Pro (Copilot)"),
    ("gpt-5.2-pro", "GPT-5.2 Pro (Copilot)"),
    ("o1", "o1 (Copilot)"),
    ("o1-mini", "o1-mini (Copilot)"),
    ("o3-mini", "o3-mini (Copilot)"),
    ("claude-sonnet-4", "Claude Sonnet 4 (Copilot)"),
    ("gemini-2.0-flash", "Gemini 2.0 Flash (Copilot)"),
];

async fn fetch_valid_copilot_token(
    client: &reqwest::Client,
    token_store: &TokenStore,
) -> anyhow::Result<String> {
    ...
}

async fn fetch_valid_copilot_token_with_fallback(
    client: &reqwest::Client,
    primary_store: &TokenStore,
) -> anyhow::Result<String> {
    ...
}

pub fn default_model_catalog() -> Vec<super::DiscoveredModel> {
    ...
}

fn normalize_display_name(model_id: &str, display_name: Option<&str>) -> String {
    ...
}

fn is_likely_model_id(model_id: &str) -> bool {
    ...
}

fn parse_model_entry(entry: &serde_json::Value) -> Option<super::DiscoveredModel> {
    ...
}

fn collect_candidate_arrays<'a>(
    value: &'a serde_json::Value,
    out: &mut Vec<&'a serde_json::Value>,
) {
    match value {
        serde_json::Value::Array(items) => out.extend(items),
        serde_json::Value::Object(map) => {
            for key in ["models", "data", "items", "results", "available"] {
                if let Some(nested) = map.get(key) {
                    collect_candidate_arrays(nested, out);
                }
            }
        },
        _ => {},
    }
}

fn parse_models_payload(value: &serde_json::Value) -> Vec<super::DiscoveredModel> {
    ...
}

async fn fetch_models_from_api(
    client: &reqwest::Client,
    access_token: String,
) -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

/// Spawn model discovery in a background thread and return the receiver
/// immediately, without blocking.
pub fn start_model_discovery() -> mpsc::Receiver<anyhow::Result<Vec<super::DiscoveredModel>>> {
    ...
}

fn fetch_models_blocking() -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

pub fn live_models() -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

pub fn available_models() -> Vec<super::DiscoveredModel> {
    ...
}

// ── Responses API helpers ────────────────────────────────────────────────────

/// Returns `true` if the given model is known to require the Responses API
/// (`/responses`) instead of Chat Completions (`/chat/completions`).
fn needs_responses_api(model: &str) -> bool {
    ...
}

/// Returns `true` if an error body from the Chat Completions API indicates
/// that the model only supports the Responses API.
fn is_responses_api_required_error(body: &str) -> bool {
    ...
}

// ── LlmProvider impl ────────────────────────────────────────────────────────

#[async_trait]
impl LlmProvider for GitHubCopilotProvider {
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

impl GitHubCopilotProvider {
    /// Non-streaming completion via the Responses API (`/responses`).
    async fn complete_responses(
        &self,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
    ) -> anyhow::Result<CompletionResponse> {

    /// Streaming via the Responses API (`/responses`) with SSE.
    fn stream_responses_api(
        &self,
        messages: Vec<ChatMessage>,
        tools: Vec<serde_json::Value>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

    /// Streaming via the Chat Completions API (`/chat/completions`) with SSE.
    #[allow(clippy::collapsible_if)]
    fn stream_chat_completions(
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
