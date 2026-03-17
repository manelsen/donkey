use std::{collections::HashSet, pin::Pin, sync::mpsc, time::Duration};

use {
    async_trait::async_trait,
    base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD},
    futures::StreamExt,
    moltis_config::schema::ProviderStreamTransport,
    moltis_oauth::{OAuthFlow, TokenStore, load_oauth_config},
    secrecy::{ExposeSecret, Secret},
    tokio_stream::Stream,
    tracing::{debug, info, trace, warn},
};

use moltis_agents::model::{
    ChatMessage, CompletionResponse, LlmProvider, StreamEvent, ToolCall, Usage, UserContent,
};

use crate::openai_compat::to_responses_api_tools;

pub struct OpenAiCodexProvider {
    ...
}

const CODEX_MODELS_ENDPOINT: &str = "https://chatgpt.com/backend-api/codex/models";
/// Report a client version that satisfies the Codex API's
/// `minimal_client_version` filter so all available models are returned.
/// Using the crate's own version (0.x) caused the API to hide newer models
/// that require >= 0.98.0.  See <https://github.com/moltis-org/moltis/issues/354>.
///
/// **DO NOT** change this to `env!("CARGO_PKG_VERSION")` — the crate version
/// is unrelated to the Codex client version and will break model discovery.
const CODEX_MODELS_CLIENT_VERSION: &str = "1.0.0";

const DEFAULT_CODEX_MODELS: &[(&str, &str)] = &[
    ("gpt-5.4", "GPT-5.4"),
    ("gpt-5.3-codex-spark", "GPT-5.3 Codex Spark"),
    ("gpt-5.3-codex", "GPT-5.3 Codex"),
    ("gpt-5.2-codex", "GPT-5.2 Codex"),
    ("gpt-5.2", "GPT-5.2"),
    ("gpt-5.1-codex-max", "GPT-5.1 Codex Max"),
    ("gpt-5.1-codex-mini", "GPT-5.1 Codex Mini"),
];

impl OpenAiCodexProvider {
    pub fn new(model: String) -> Self {

    pub fn new_with_transport(model: String, stream_transport: ProviderStreamTransport) -> Self {
    ...
}

    fn ensure_supported_stream_transport(&self) -> anyhow::Result<()> {
    ...
}

    async fn get_valid_tokens(&self) -> anyhow::Result<moltis_oauth::OAuthTokens> {
    ...
}

    fn extract_account_id_from_claims(claims: &serde_json::Value) -> Option<String> {
    ...
}

    fn extract_account_id(jwt: &str) -> Option<String> {
    ...
}

    fn resolve_account_id(tokens: &moltis_oauth::OAuthTokens) -> anyhow::Result<String> {
    ...
}

    fn convert_messages(messages: &[ChatMessage]) -> Vec<serde_json::Value> {
    ...
}

    async fn post_responses_request(
        &self,
        token: &str,
        account_id: &str,
        body: &serde_json::Value,
    ) -> Result<reqwest::Response, reqwest::Error> {
    ...
}

    async fn post_responses_request_with_fallback(
        &self,
        token: &str,
        account_id: &str,
        body: serde_json::Value,
    ) -> anyhow::Result<reqwest::Response> {
    ...
}
}

/// Parse tokens from Codex CLI auth.json content.
fn parse_codex_cli_tokens(data: &str) -> Option<moltis_oauth::OAuthTokens> {
    ...
}

/// Try to load tokens from the Codex CLI file at `~/.codex/auth.json`.
fn load_codex_cli_tokens() -> Option<moltis_oauth::OAuthTokens> {
    ...
}

pub fn has_stored_tokens() -> bool {
    ...
}

pub fn default_model_catalog() -> Vec<super::DiscoveredModel> {
    ...
}

fn formatted_model_name(model_id: &str) -> String {
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
    access_token: String,
    account_id: String,
) -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

/// Spawn model discovery in a background thread and return the receiver
/// immediately, without blocking. Returns `None` if tokens are not configured.
pub fn start_model_discovery() -> Option<mpsc::Receiver<anyhow::Result<Vec<super::DiscoveredModel>>>>
    ...
}

fn fetch_models_blocking(
    access_token: String,
    account_id: String,
) -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

fn load_access_token_and_account_id() -> anyhow::Result<(String, String)> {
    ...
}

pub fn live_models() -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

pub fn available_models() -> Vec<super::DiscoveredModel> {
    ...
}

#[async_trait]
impl LlmProvider for OpenAiCodexProvider {
    fn name(&self) -> &str {

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

    #[test]
    fn parse_codex_cli_tokens_full() {
    ...
}

    #[test]
    fn parse_codex_cli_tokens_no_refresh() {
    ...
}

    #[test]
    fn extract_account_id_supports_root_nested_and_org_claims() {
    ...
}

    #[test]
    fn parse_codex_cli_tokens_missing_tokens_field() {
    ...
}

    #[test]
    fn parse_codex_cli_tokens_invalid_json() {
    ...
}

    #[test]
    fn parse_codex_cli_tokens_null_access_token() {
    ...
}

    #[test]
    fn convert_messages_user_and_assistant() {
    ...
}

    #[test]
    fn convert_messages_tool_call_and_result() {
    ...
}

    // ── Array Content Handling Tests ───────────────────────────────────
    // These tests verify that the Codex provider correctly handles array
    // content (multimodal) in tool results, which can occur even when we
    // send string content due to model behavior or content format.

    #[test]
    fn convert_messages_tool_result_with_string_content() {
    ...
}

    #[test]
    fn convert_messages_tool_result_with_serialized_array_content() {
    ...
}

    #[test]
    fn convert_messages_tool_result_with_empty_content() {
    ...
}

    #[test]
    fn convert_messages_tool_result_with_json_object_content() {
    ...
}

    #[test]
    fn convert_messages_preserves_tool_call_id() {
    ...
}

    #[test]
    fn convert_messages_empty_array_content() {
    ...
}

    #[test]
    fn convert_messages_mixed_conversation_with_tool_content() {
    ...
}

    #[test]
    fn convert_messages_user_multimodal_with_image() {
    ...
}

    #[test]
    fn client_version_satisfies_codex_minimum() {
    ...
}

    #[test]
    fn default_codex_models_includes_latest() {
    ...
}

    #[test]
    fn parse_models_payload_from_models_array() {
    ...
}

    #[test]
    fn parse_models_payload_from_nested_data_array() {
    ...
}

    #[test]
    fn parse_models_payload_ignores_invalid_ids_and_dedupes() {
    ...
}

    #[test]
    fn parse_models_payload_keeps_non_codex_and_codex_variants() {
    ...
}
}
