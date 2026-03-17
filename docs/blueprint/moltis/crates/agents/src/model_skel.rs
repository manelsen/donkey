use std::{pin::Pin, sync::Arc};

use {async_trait::async_trait, tokio_stream::Stream};

use crate::multimodal::parse_data_uri;

// ── Reasoning effort ──────────────────────────────────────────────────────

/// Re-export from config so downstream crates can use `moltis_agents::model::ReasoningEffort`.
pub use moltis_config::schema::ReasoningEffort;

// ── Typed chat messages ─────────────────────────────────────────────────────

/// Typed chat message for the LLM provider interface.
///
/// Only contains LLM-relevant fields — metadata like `created_at`, `model`,
/// `provider`, `inputTokens`, `outputTokens` cannot exist here, so they
/// can never leak into provider API requests.
#[derive(Debug, Clone)]
pub enum ChatMessage {
    ...
}

/// User message content: plain text or multimodal (text + images).
#[derive(Debug, Clone)]
pub enum UserContent {
    ...
}

impl UserContent {
    /// Create a text-only user content.
    pub fn text(s: impl Into<String>) -> Self {
}

/// A single part of a multimodal content array.
#[derive(Debug, Clone)]
pub enum ContentPart {
    ...
}

impl ChatMessage {
    /// Create a system message.
    pub fn system(content: impl Into<String>) -> Self {

    /// Create a user message with plain text.
    pub fn user(content: impl Into<String>) -> Self {
    ...
}

    /// Create a user message with multimodal content.
    pub fn user_multimodal(parts: Vec<ContentPart>) -> Self {
    ...
}

    /// Create an assistant message with text only (no tool calls).
    pub fn assistant(content: impl Into<String>) -> Self {
    ...
}

    /// Create an assistant message with tool calls (and optional text).
    pub fn assistant_with_tools(content: Option<String>, tool_calls: Vec<ToolCall>) -> Self {
    ...
}

    /// Create a tool result message.
    pub fn tool(tool_call_id: impl Into<String>, content: impl Into<String>) -> Self {
    ...
}

    /// Convert to OpenAI-compatible JSON format.
    ///
    /// Used by providers that speak the OpenAI Chat Completions API:
    /// OpenAI, Mistral, Copilot, Kimi, Cerebras, etc.
    #[must_use]
    pub fn to_openai_value(&self) -> serde_json::Value {
    ...
}
}

/// Convert persisted JSON messages (from session store) to typed `ChatMessage`s.
///
/// Skips messages that don't have a valid `role` field, logging a warning.
/// Metadata fields (`created_at`, `model`, `provider`, `inputTokens`,
/// `outputTokens`, `channel`) are silently dropped — they only exist in
/// the persisted JSON, not in `ChatMessage`.
pub fn values_to_chat_messages(values: &[serde_json::Value]) -> Vec<ChatMessage> {
    ...
}

// ── Stream events ───────────────────────────────────────────────────────────

/// Events emitted during streaming LLM completion.
#[derive(Debug, Clone)]
pub enum StreamEvent {
    ...
}

/// LLM provider trait (Anthropic, OpenAI, Google, etc.).
#[async_trait]
pub trait LlmProvider: Send + Sync {
    fn name(&self) -> &str;

    /// Model identifier (e.g. "claude-sonnet-4-20250514", "gpt-4o").
    fn id(&self) -> &str;

    async fn complete(
        &self,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
    ) -> anyhow::Result<CompletionResponse>;

    /// Whether this provider supports tool/function calling.
    /// Defaults to false; providers that handle the `tools` parameter
    /// in `complete()` should override this to return true.
    fn supports_tools(&self) -> bool {
    ...
}

    /// Context window size in tokens for this model.
    /// Used to detect when conversation approaches the limit and trigger auto-compact.
    fn context_window(&self) -> u32 {
    ...
}

    /// Whether this provider supports vision (image inputs).
    /// When true, tool results containing images will be sent as multimodal
    /// content blocks instead of stripping the image data.
    fn supports_vision(&self) -> bool {
    ...
}

    /// Configured tool mode for this provider, if any.
    ///
    /// Returns `None` when the provider has no explicit tool mode override
    /// (the caller should fall back to `Auto` behavior based on `supports_tools()`).
    fn tool_mode(&self) -> Option<moltis_config::ToolMode> {
    ...
}

    /// Stream a completion, yielding delta/done/error events.
    fn stream(
        &self,
        messages: Vec<ChatMessage>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>>;

    /// Stream a completion with tool support.
    ///
    /// Like `stream()`, but accepts tool schemas and can emit `ToolCallStart`,
    /// `ToolCallArgumentsDelta`, and `ToolCallComplete` events in addition to
    /// text deltas.
    ///
    /// Default implementation falls back to `stream()` (ignoring tools).
    /// Providers with native streaming tool support should override this.
    fn stream_with_tools(
        &self,
        messages: Vec<ChatMessage>,
        _tools: Vec<serde_json::Value>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

    /// Configured reasoning effort for this provider instance, if any.
    ///
    /// Providers that support extended thinking (Anthropic, OpenAI o-series)
    /// use this value when building API requests.
    fn reasoning_effort(&self) -> Option<ReasoningEffort> {
    ...
}

    /// Return a new provider with reasoning effort set, if supported.
    ///
    /// Returns `None` for providers that don't support reasoning effort.
    /// Used by sub-agent spawning to apply per-agent reasoning settings
    /// without mutating the shared registry provider.
    fn with_reasoning_effort(
        self: Arc<Self>,
        _effort: ReasoningEffort,
    ) -> Option<Arc<dyn LlmProvider>> {
    ...
}

    /// Fetch runtime model metadata from the provider API.
    ///
    /// The default implementation returns a `ModelMetadata` derived from the
    /// static `context_window()` value. Providers that support a `/models`
    /// endpoint can override this to fetch the actual context length at runtime.
    async fn model_metadata(&self) -> anyhow::Result<ModelMetadata> {
    ...
}
}

/// Response from an LLM completion call.
#[derive(Debug)]
pub struct CompletionResponse {
    ...
}

#[derive(Debug, Clone)]
pub struct ToolCall {
    ...
}

#[derive(Debug, Clone, Default)]
pub struct Usage {
    ...
}

/// Runtime model metadata fetched from provider APIs.
#[derive(Debug, Clone)]
pub struct ModelMetadata {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn user_message_text() {
    ...
}

    #[test]
    fn assistant_message_text() {
    ...
}

    #[test]
    fn tool_message() {
    ...
}

    // ── to_openai_value ──────────────────────────────────────────────

    #[test]
    fn to_openai_system() {
    ...
}

    #[test]
    fn to_openai_user_text() {
    ...
}

    #[test]
    fn to_openai_user_multimodal() {
    ...
}

    #[test]
    fn to_openai_assistant_text() {
    ...
}

    #[test]
    fn to_openai_assistant_with_tools() {
    ...
}

    #[test]
    fn to_openai_tool() {
    ...
}

    // ── values_to_chat_messages ──────────────────────────────────────

    #[test]
    fn convert_basic_messages() {
    ...
}

    #[test]
    fn convert_skips_metadata_fields() {
    ...
}

    #[test]
    fn convert_assistant_with_tool_calls() {
    ...
}

    #[test]
    fn convert_tool_message() {
    ...
}

    #[test]
    fn convert_skips_invalid_messages() {
    ...
}

    #[test]
    fn roundtrip_to_openai_and_back() {
    ...
}

    /// Verify that user content containing role-like prefixes (e.g. injected
    /// `\nassistant:` lines) remains inside a User message and does NOT produce
    /// a separate Assistant turn. This is the structural defence against the
    /// OpenClaw-style sender-spoofing prompt injection (GHSA-g8p2-7wf7-98mq).
    #[test]
    fn injected_role_prefix_stays_in_user_message() {
    ...
}

    #[test]
    fn convert_includes_tool_result_with_matching_assistant() {
    ...
}

    #[test]
    fn convert_skips_orphan_tool_result() {
    ...
}

    #[test]
    fn convert_skips_notice_entries() {
    ...
}

    #[test]
    fn convert_tool_result_to_tool_message() {
    ...
}

    #[test]
    fn convert_tool_result_error_to_tool_message() {
    ...
}

    // ── ModelMetadata default trait impl ────────────────────────────

    /// Minimal provider to test default `model_metadata()` behavior.
    struct StubProvider;

    #[async_trait::async_trait]
    impl LlmProvider for StubProvider {
        fn name(&self) -> &str {
    ...
}

        fn id(&self) -> &str {
    ...
}

        fn context_window(&self) -> u32 {
    ...
}

        async fn complete(
            &self,
            _: &[ChatMessage],
            _: &[serde_json::Value],
        ) -> anyhow::Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn default_model_metadata_returns_context_window() {
    ...
}
}
