use std::pin::Pin;

use {async_trait::async_trait, futures::StreamExt, secrecy::ExposeSecret, tokio_stream::Stream};

use tracing::{debug, trace, warn};

use moltis_agents::model::{
    ChatMessage, CompletionResponse, ContentPart, LlmProvider, StreamEvent, ToolCall, Usage,
    UserContent,
};

pub struct AnthropicProvider {
    ...
}

impl AnthropicProvider {
    pub fn new(api_key: secrecy::Secret<String>, model: String, base_url: String) -> Self {

    /// Create a new provider with a custom alias for metrics.
    pub fn with_alias(
        api_key: secrecy::Secret<String>,
        model: String,
        base_url: String,
        alias: Option<String>,
    ) -> Self {
    ...
}

    /// Apply `thinking` configuration to an Anthropic request body based on
    /// the configured reasoning effort.
    fn apply_thinking(&self, body: &mut serde_json::Value) {
    ...
}
}

/// Convert tool schemas from the generic format to Anthropic's tool format.
fn to_anthropic_tools(tools: &[serde_json::Value]) -> Vec<serde_json::Value> {
    ...
}

/// Parse tool_use blocks from an Anthropic response.
fn parse_tool_calls(content: &[serde_json::Value]) -> Vec<ToolCall> {
    ...
}

fn retry_after_ms_from_headers(headers: &reqwest::header::HeaderMap) -> Option<u64> {
    ...
}

fn with_retry_after_marker(base: String, retry_after_ms: Option<u64>) -> String {
    ...
}

/// Convert `ChatMessage` list to Anthropic format.
///
/// Returns `(system_text, anthropic_messages)`. System messages are extracted
/// (Anthropic takes them as a top-level `system` field). Tool messages become
/// user messages with `tool_result` content blocks. Assistant messages with
/// tool calls become `content` arrays with `tool_use` blocks.
fn to_anthropic_messages(messages: &[ChatMessage]) -> (Option<String>, Vec<serde_json::Value>) {
    ...
}

#[async_trait]
impl LlmProvider for AnthropicProvider {
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

    fn context_window(&self) -> u32 {
    ...
}

    fn supports_vision(&self) -> bool {
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
    fn retry_after_ms_from_headers_ignores_non_numeric_values() {
    ...
}

    #[test]
    fn with_retry_after_marker_appends_retry_hint() {
    ...
}

    #[test]
    fn apply_thinking_injects_budget_for_high_effort() {
    ...
}

    #[test]
    fn apply_thinking_skipped_when_no_effort() {
    ...
}

    #[test]
    fn apply_thinking_low_effort_budget() {
    ...
}

    #[test]
    fn with_reasoning_effort_creates_new_provider() {
    ...
}
}
