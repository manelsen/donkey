use std::{
    collections::{HashMap, HashSet},
    pin::Pin,
    sync::mpsc,
    time::Duration,
};

use {
    async_trait::async_trait,
    futures::{SinkExt, StreamExt},
    moltis_config::schema::ProviderStreamTransport,
    secrecy::ExposeSecret,
    tokio_stream::Stream,
    tokio_tungstenite::tungstenite::{Message, client::IntoClientRequest, http::HeaderValue},
};

use tracing::{debug, trace, warn};

use {
    super::openai_compat::{
        SseLineResult, StreamingToolState, finalize_stream, parse_openai_compat_usage,
        parse_openai_compat_usage_from_payload, parse_tool_calls, process_openai_sse_line,
        responses_output_index, split_responses_instructions_and_input, strip_think_tags,
        to_openai_tools, to_responses_api_tools,
    },
    moltis_agents::model::{
        ChatMessage, CompletionResponse, LlmProvider, ModelMetadata, StreamEvent, Usage,
    },
};

pub struct OpenAiProvider {
    ...
}

const OPENAI_MODELS_ENDPOINT_PATH: &str = "/models";

#[derive(Clone, Copy)]
struct ModelCatalogEntry {
    ...
}

impl ModelCatalogEntry {
    const fn new(id: &'static str, display_name: &'static str) -> Self {
}

const DEFAULT_OPENAI_MODELS: &[ModelCatalogEntry] = &[
    ModelCatalogEntry::new("gpt-5.2", "GPT-5.2"),
    ModelCatalogEntry::new("gpt-5.2-chat-latest", "GPT-5.2 Chat Latest"),
    ModelCatalogEntry::new("gpt-5-mini", "GPT-5 Mini"),
];

#[must_use]
pub fn default_model_catalog() -> Vec<super::DiscoveredModel> {
    ...
}

fn title_case_chunk(chunk: &str) -> String {
    ...
}

fn format_gpt_display_name(model_id: &str) -> String {
    ...
}

fn format_chatgpt_display_name(model_id: &str) -> String {
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

/// Delegates to the shared [`super::is_chat_capable_model`] for filtering
/// non-chat models during discovery.
fn is_chat_capable_model(model_id: &str) -> bool {
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

fn is_chat_endpoint_unsupported_model_error(body_text: &str) -> bool {
    ...
}

fn should_warn_on_api_error(status: reqwest::StatusCode, body_text: &str) -> bool {
    ...
}

const OPENAI_MAX_TOOL_CALL_ID_LEN: usize = 40;

fn short_stable_hash(value: &str) -> String {
    ...
}

fn base_openai_tool_call_id(raw: &str) -> String {
    ...
}

fn disambiguate_tool_call_id(base: &str, nonce: usize) -> String {
    ...
}

fn assign_openai_tool_call_id(
    raw: &str,
    remapped_tool_call_ids: &mut HashMap<String, String>,
    used_tool_call_ids: &mut HashSet<String>,
) -> String {
    ...
}

fn models_endpoint(base_url: &str) -> String {
    ...
}

/// Resolve the output index from a Responses API WebSocket streaming event.
///
/// The Responses API includes `output_index` on most events. Falls back to
/// `item_index` / `index` for robustness, then to `fallback`.
async fn fetch_models_from_api(
    api_key: secrecy::Secret<String>,
    base_url: String,
) -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

/// Spawn model discovery in a background thread and return the receiver
/// immediately, without blocking. Call `.recv()` later to collect the result.
pub fn start_model_discovery(
    api_key: secrecy::Secret<String>,
    base_url: String,
) -> mpsc::Receiver<anyhow::Result<Vec<super::DiscoveredModel>>> {
    ...
}

fn fetch_models_blocking(
    api_key: secrecy::Secret<String>,
    base_url: String,
) -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

pub fn live_models(
    api_key: &secrecy::Secret<String>,
    base_url: &str,
) -> anyhow::Result<Vec<super::DiscoveredModel>> {
    ...
}

#[must_use]
pub fn available_models(
    api_key: &secrecy::Secret<String>,
    base_url: &str,
) -> Vec<super::DiscoveredModel> {
    ...
}

impl OpenAiProvider {
    pub fn new(api_key: secrecy::Secret<String>, model: String, base_url: String) -> Self {

    pub fn new_with_name(
        api_key: secrecy::Secret<String>,
        model: String,
        base_url: String,
        provider_name: String,
    ) -> Self {
    ...
}

    #[must_use]
    pub fn with_stream_transport(mut self, stream_transport: ProviderStreamTransport) -> Self {
    ...
}

    #[must_use]
    pub fn with_tool_mode(mut self, mode: moltis_config::ToolMode) -> Self {
    ...
}

    /// Return the reasoning effort string if configured.
    fn reasoning_effort_str(&self) -> Option<&'static str> {
    ...
}

    /// Apply `reasoning_effort` for the **Chat Completions** API (used by
    /// `complete()` and `stream_with_tools_sse()`).
    ///
    /// Format: `"reasoning_effort": "high"` (top-level string field).
    fn apply_reasoning_effort_chat(&self, body: &mut serde_json::Value) {
    ...
}

    /// Apply `reasoning_effort` for the **Responses** API (used by
    /// `stream_with_tools_websocket()`).
    ///
    /// Format: `"reasoning": { "effort": "high" }` (nested object).
    fn apply_reasoning_effort_responses(&self, body: &mut serde_json::Value) {
    ...
}

    fn requires_reasoning_content_on_tool_messages(&self) -> bool {
    ...
}

    fn requires_top_level_system_prompt(&self) -> bool {
    ...
}

    fn prepare_request_messages(
        &self,
        messages: Vec<serde_json::Value>,
    ) -> (Vec<serde_json::Value>, Option<String>) {
    ...
}

    fn serialize_messages_for_request(&self, messages: &[ChatMessage]) -> Vec<serde_json::Value> {
    ...
}

    fn is_openai_platform_base_url(&self) -> bool {
    ...
}

    fn responses_websocket_url(&self) -> crate::error::Result<String> {
    ...
}

    #[allow(clippy::collapsible_if)]
    fn stream_with_tools_sse(
        &self,
        messages: Vec<ChatMessage>,
        tools: Vec<serde_json::Value>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

    #[allow(clippy::collapsible_if)]
    fn stream_with_tools_websocket(
        &self,
        messages: Vec<ChatMessage>,
        tools: Vec<serde_json::Value>,
        fallback_to_sse: bool,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
}

#[async_trait]
impl LlmProvider for OpenAiProvider {
    fn name(&self) -> &str {

    fn reasoning_effort(&self) -> Option<moltis_agents::model::ReasoningEffort> {
    ...
}

    fn with_reasoning_effort(
        self: std::sync::Arc<Self>,
        effort: moltis_agents::model::ReasoningEffort,
    ) -> Option<std::sync::Arc<dyn LlmProvider>> {
    ...
}

    fn id(&self) -> &str {
    ...
}

    fn supports_tools(&self) -> bool {
    ...
}

    fn tool_mode(&self) -> Option<moltis_config::ToolMode> {
    ...
}

    fn context_window(&self) -> u32 {
    ...
}

    fn supports_vision(&self) -> bool {
    ...
}

    async fn model_metadata(&self) -> anyhow::Result<ModelMetadata> {
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
