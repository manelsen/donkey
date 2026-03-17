use std::{fmt::Write, sync::Arc};

use {
    anyhow::{Result, bail},
    tracing::{debug, info, trace, warn},
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram, labels, llm as llm_metrics};

use moltis_common::hooks::{HookAction, HookPayload, HookRegistry};

use crate::{
    model::{
        ChatMessage, CompletionResponse, LlmProvider, StreamEvent, ToolCall, Usage, UserContent,
    },
    response_sanitizer::{clean_response, recover_tool_calls_from_content},
    tool_parsing::{
        looks_like_failed_tool_call, new_synthetic_tool_call_id, parse_tool_calls_from_text,
    },
    tool_registry::ToolRegistry,
};

use futures::StreamExt;

/// Fallback loop limit when config is missing or invalid.
const DEFAULT_AGENT_MAX_ITERATIONS: usize = 25;

fn resolve_agent_max_iterations(configured: usize) -> usize {
    ...
}

/// Sanitize a tool name from model output: trim whitespace and strip
/// surrounding quotes that some models wrap around tool names.
fn sanitize_tool_name(name: &str) -> &str {
    ...
}

const MALFORMED_TOOL_RETRY_PROMPT: &str = "Your tool call was malformed. Retry with exact format:\n\
     ```tool_call\n{\"tool\": \"name\", \"arguments\": {...}}\n```";
const EMPTY_TOOL_NAME_RETRY_PROMPT: &str = "Your structured tool call had an empty tool name. Retry the same tool call using the intended tool's exact name and the same arguments.";

fn find_empty_tool_name_call(tool_calls: &[ToolCall]) -> Option<&ToolCall> {
    ...
}

fn has_named_tool_call(tool_calls: &[ToolCall]) -> bool {
    ...
}

fn empty_tool_name_retry_prompt(tool_call: &ToolCall) -> String {
    ...
}

fn record_answer_text(last_answer_text: &mut String, text: &Option<String>) {
    ...
}

fn streaming_tool_call_message_content(
    last_answer_text: &mut String,
    accumulated_text: &str,
    accumulated_reasoning: &str,
) -> Option<String> {
    ...
}

/// Error patterns that indicate the context window has been exceeded.
const CONTEXT_WINDOW_PATTERNS: &[&str] = &[
    "context_length_exceeded",
    "max_tokens",
    "too many tokens",
    "request too large",
    "maximum context length",
    "context window",
    "token limit",
    "content_too_large",
    "request_too_large",
];

/// Check if an error message indicates a context window overflow.
fn is_context_window_error(msg: &str) -> bool {
    ...
}

/// Error patterns that indicate a transient server error worth retrying.
const RETRYABLE_SERVER_PATTERNS: &[&str] = &[
    "http 500",
    "http 502",
    "http 503",
    "http 529",
    "server_error",
    "internal server error",
    "overloaded",
    "bad gateway",
    "service unavailable",
    "the server had an error processing your request",
];

/// Check if an error looks like a transient provider failure that may
/// succeed on retry (5xx, overloaded, etc.).
fn is_retryable_server_error(msg: &str) -> bool {
    ...
}

/// Error patterns that indicate provider-side rate limiting.
const RATE_LIMIT_PATTERNS: &[&str] = &[
    "http 429",
    "status=429",
    "status 429",
    "status: 429",
    "too many requests",
    "rate limit",
    "rate_limit",
];

fn is_rate_limit_error(msg: &str) -> bool {
    ...
}

/// Error patterns that indicate the account is out of credits/quota.
/// These are not retryable in the short term and should surface directly.
const BILLING_QUOTA_PATTERNS: &[&str] = &[
    "insufficient_quota",
    "quota exceeded",
    "current quota",
    "billing details",
    "billing limit",
    "credit balance",
];

fn is_billing_quota_error(msg: &str) -> bool {
    ...
}

/// Base delay for non-rate-limit transient retries.
const SERVER_RETRY_DELAY: std::time::Duration = std::time::Duration::from_secs(2);

/// Rate-limit retries use exponential backoff with a cap.
const RATE_LIMIT_INITIAL_RETRY_MS: u64 = 2_000;
const RATE_LIMIT_MAX_RETRY_MS: u64 = 60_000;
const RATE_LIMIT_MAX_RETRIES: u8 = 10;

fn next_rate_limit_retry_ms(previous_ms: Option<u64>) -> u64 {
    ...
}

fn parse_retry_delay_ms_from_fragment(
    fragment: &str,
    unit_default_ms: bool,
    max_ms: u64,
) -> Option<u64> {
    ...
}

/// Extract retry delay hints embedded in provider error messages.
///
/// Supports patterns like:
/// - `retry_after_ms=1234`
/// - `Retry-After: 30`
/// - `retry after 30s`
/// - `retry in 45 seconds`
fn extract_retry_after_ms(msg: &str, max_ms: u64) -> Option<u64> {
    ...
}

fn next_retry_delay_ms(
    msg: &str,
    server_retries_remaining: &mut u8,
    rate_limit_retries_remaining: &mut u8,
    rate_limit_backoff_ms: &mut Option<u64>,
) -> Option<u64> {
    ...
}

/// Typed errors from the agent loop.
#[derive(Debug, thiserror::Error)]
pub enum AgentRunError {
    ...
}

/// Result of running the agent loop.
#[derive(Debug)]
pub struct AgentRunResult {
    ...
}

/// Callback for streaming events out of the runner.
pub type OnEvent = Box<dyn Fn(RunnerEvent) + Send + Sync>;

/// Events emitted during the agent run.
#[derive(Debug, Clone)]
pub enum RunnerEvent {
    ...
}

/// Detect an explicit shell command in the latest user turn.
///
/// Only `/sh ...` commands are treated as explicit shell execution requests.
/// This keeps normal chat turns (`hey`, `hello`, etc.) out of the forced-exec path.
///
/// Supported forms:
/// - `/sh pwd`
/// - `/sh@mybot uname -a`
fn explicit_shell_command_from_user_content(user_content: &UserContent) -> Option<String> {
    ...
}

// ── Tool result sanitization ────────────────────────────────────────────

/// Tag that starts a base64 data URI.
const BASE64_TAG: &str = "data:";
/// Marker between MIME type and base64 payload.
const BASE64_MARKER: &str = ";base64,";
/// Minimum length of a blob payload (base64 or hex) to be worth stripping.
const BLOB_MIN_LEN: usize = 200;

fn is_base64_byte(b: u8) -> bool {
    ...
}

/// Strip base64 data-URI blobs (e.g. `data:image/png;base64,AAAA...`) and
/// replace them with a short placeholder. Only targets payloads ≥ 200 chars.
fn strip_base64_blobs(input: &str) -> String {
    ...
}

/// Strip long hex sequences (≥ 200 hex chars) that look like binary dumps.
fn strip_hex_blobs(input: &str) -> String {
    ...
}

/// Sanitize a tool result string before feeding it to the LLM.
///
/// 1. Strips base64 data URIs (≥ 200 char payloads).
/// 2. Strips long hex sequences (≥ 200 hex chars).
/// 3. Truncates the result to `max_bytes` (at a char boundary), appending a
///    truncation marker.
pub fn sanitize_tool_result(input: &str, max_bytes: usize) -> String {
    ...
}

// ── Multimodal tool result helpers ─────────────────────────────────────────

/// Image extracted from a tool result for multimodal handling.
#[derive(Debug)]
pub struct ExtractedImage {
    ...
}

/// Extract image data URIs from text, returning the images and remaining text.
///
/// Searches for patterns like `data:image/png;base64,AAAA...` and extracts them.
/// Returns the list of images found and the text with images removed.
fn extract_images_from_text_impl(input: &str) -> (Vec<ExtractedImage>, String) {
    ...
}

/// Test alias for extract_images_from_text_impl
#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
fn extract_images_from_text(input: &str) -> (Vec<ExtractedImage>, String) {
    ...
}

/// Convert a tool result to multimodal content for vision-capable providers.
///
/// For providers with `supports_vision() == true`, this extracts images from
/// the tool result and returns them as OpenAI-style content blocks:
/// ```json
/// [
///   { "type": "text", "text": "..." },
///   { "type": "image_url", "image_url": { "url": "data:image/png;base64,..." } }
/// ]
/// ```
///
/// For non-vision providers, returns a simple string with images stripped.
///
/// Note: Browser screenshots are pre-stripped by the browser tool to avoid
/// the LLM outputting the raw base64 in its response (the UI already displays
/// screenshots via WebSocket events).
pub fn tool_result_to_content(
    result: &str,
    max_bytes: usize,
    supports_vision: bool,
) -> serde_json::Value {
    ...
}

/// Run the agent loop: send messages to the LLM, execute tool calls, repeat.
///
/// If `history` is provided, those messages are inserted between the system
/// prompt and the current user message, giving the LLM conversational context.
pub async fn run_agent_loop(
    provider: Arc<dyn LlmProvider>,
    tools: &ToolRegistry,
    system_prompt: &str,
    user_content: &UserContent,
    on_event: Option<&OnEvent>,
    history: Option<Vec<ChatMessage>>,
) -> Result<AgentRunResult, AgentRunError> {
    ...
}

/// Like `run_agent_loop` but accepts optional context values that are injected
/// into every tool call's parameters (e.g. `_session_key`).
pub async fn run_agent_loop_with_context(
    provider: Arc<dyn LlmProvider>,
    tools: &ToolRegistry,
    system_prompt: &str,
    user_content: &UserContent,
    on_event: Option<&OnEvent>,
    history: Option<Vec<ChatMessage>>,
    tool_context: Option<serde_json::Value>,
    hook_registry: Option<Arc<HookRegistry>>,
) -> Result<AgentRunResult, AgentRunError> {
    ...
}

/// Convenience wrapper matching the old stub signature.
pub async fn run_agent(_agent_id: &str, _session_key: &str, _message: &str) -> Result<String> {
    ...
}

/// Streaming variant of the agent loop.
///
/// Unlike `run_agent_loop_with_context`, this function uses streaming to send
/// text deltas to the UI as they arrive, providing a much better UX.
///
/// Tool calls are accumulated from the stream and executed after the stream
/// completes, then the loop continues with the next iteration.
pub async fn run_agent_loop_streaming(
    provider: Arc<dyn LlmProvider>,
    tools: &ToolRegistry,
    system_prompt: &str,
    user_content: &UserContent,
    on_event: Option<&OnEvent>,
    history: Option<Vec<ChatMessage>>,
    tool_context: Option<serde_json::Value>,
    hook_registry: Option<Arc<HookRegistry>>,
) -> Result<AgentRunResult, AgentRunError> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    // ── parse_tool_call_from_text tests (delegates to tool_parsing) ──

    #[test]
    fn test_parse_tool_call_basic() {
    ...
}

    #[test]
    fn test_parse_tool_call_with_surrounding_text() {
    ...
}

    #[test]
    fn test_parse_tool_call_no_block() {
    ...
}

    #[test]
    fn test_parse_tool_call_invalid_json() {
    ...
}

    #[test]
    fn test_parse_tool_call_function_block() {
    ...
}

    #[test]
    fn test_new_synthetic_tool_call_id_is_openai_compatible() {
    ...
}

    #[test]
    fn test_parse_tool_call_function_block_with_wrapper_and_text() {
    ...
}

    #[test]
    fn test_explicit_shell_command_requires_sh_prefix() {
    ...
}

    #[test]
    fn test_explicit_shell_command_extracts_command() {
    ...
}

    #[test]
    fn test_explicit_shell_command_supports_telegram_style_bot_mention() {
    ...
}

    #[test]
    fn test_resolve_agent_max_iterations_falls_back_for_zero() {
    ...
}

    // ── Mock helpers ─────────────────────────────────────────────────

    /// A mock provider that returns text on the first call.
    struct MockProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for MockProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    /// Mock provider that makes one tool call then returns text (native tool support).
    struct ToolCallingProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for ToolCallingProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    /// Non-native provider that returns tool calls as text blocks.
    struct TextToolCallingProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for TextToolCallingProvider {
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
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    /// Simple echo tool for testing.
    struct EchoTool;

    #[async_trait]
    impl crate::tool_registry::AgentTool for EchoTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, params: serde_json::Value) -> Result<serde_json::Value> {
    ...
}
    }

    /// A tool that actually runs shell commands (test-only, mirrors ExecTool).
    struct TestExecTool;

    #[async_trait]
    impl crate::tool_registry::AgentTool for TestExecTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, params: serde_json::Value) -> Result<serde_json::Value> {
    ...
}
    }

    /// Minimal process tool for testing `<function=process>` parsing.
    struct TestProcessTool;

    #[async_trait]
    impl crate::tool_registry::AgentTool for TestProcessTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, params: serde_json::Value) -> Result<serde_json::Value> {
    ...
}
    }

    // ── Tests ────────────────────────────────────────────────────────

    #[tokio::test]
    async fn test_simple_text_response() {
    ...
}

    #[tokio::test]
    async fn test_tool_call_loop() {
    ...
}

    fn last_user_text(messages: &[ChatMessage]) -> &str {
    ...
}

    fn last_tool_text(messages: &[ChatMessage]) -> &str {
    ...
}

    fn has_tool_message_containing(messages: &[ChatMessage], needle: &str) -> bool {
    ...
}

    struct EmptyToolNameProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for EmptyToolNameProvider {
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
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_empty_structured_tool_name_retries_non_streaming() {
    ...
}

    struct MalformedThenEmptyToolNameProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for MalformedThenEmptyToolNameProvider {
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
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

    #[tokio::test]
    async fn test_empty_tool_name_retry_does_not_consume_malformed_retry_budget_non_streaming() {
    ...
}

    struct EmptyToolNameRetryPreservesAnswerTextProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for EmptyToolNameRetryPreservesAnswerTextProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_empty_tool_name_retry_preserves_last_answer_text_non_streaming() {
    ...
}

    struct RepeatedEmptyToolNameProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for RepeatedEmptyToolNameProvider {
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
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_repeated_empty_tool_name_falls_back_to_unknown_tool_non_streaming() {
    ...
}

    struct MixedEmptyAndValidToolNameProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for MixedEmptyAndValidToolNameProvider {
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
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_mixed_empty_and_valid_tool_names_execute_valid_siblings_non_streaming() {
    ...
}

    struct EmptyToolNameStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for EmptyToolNameStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_empty_structured_tool_name_retries_streaming() {
    ...
}

    struct MalformedThenEmptyToolNameStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for MalformedThenEmptyToolNameStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

    #[tokio::test]
    async fn test_empty_tool_name_retry_does_not_consume_malformed_retry_budget_streaming() {
    ...
}

    struct EmptyToolNameRetryPreservesReasoningStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for EmptyToolNameRetryPreservesReasoningStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_empty_tool_name_retry_preserves_reasoning_context_streaming() {
    ...
}

    struct RepeatedEmptyToolNameStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for RepeatedEmptyToolNameStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_repeated_empty_tool_name_falls_back_to_unknown_tool_streaming() {
    ...
}

    struct MixedEmptyAndValidToolNameStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for MixedEmptyAndValidToolNameStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_mixed_empty_and_valid_tool_names_execute_valid_siblings_streaming() {
    ...
}

    /// Mock provider that calls the "exec" tool (native) and verifies result fed back.
    struct ExecSimulatingProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for ExecSimulatingProvider {
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
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_exec_tool_end_to_end() {
    ...
}

    /// Test that non-native providers can still execute tools via text parsing.
    #[tokio::test]
    async fn test_text_based_tool_calling() {
    ...
}

    /// Native-tool provider that returns plain text (no structured tool call)
    /// on the first turn for a command-like prompt.
    struct DirectCommandNoToolProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for DirectCommandNoToolProvider {
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
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_explicit_sh_command_forces_exec_non_streaming() {
    ...
}

    #[tokio::test]
    async fn test_unprefixed_command_like_text_does_not_force_exec_non_streaming() {
    ...
}

    /// Native-tool provider that emits XML-like function text instead of
    /// structured tool calls. We should still execute it via text fallback.
    struct NativeTextFunctionProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for NativeTextFunctionProvider {
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
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_native_text_function_tool_calling_non_streaming() {
    ...
}

    // ── Parallel tool execution tests ────────────────────────────────

    /// A tool that sleeps then returns its name.
    struct SlowTool {
    ...
}

    #[async_trait]
    impl crate::tool_registry::AgentTool for SlowTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, _params: serde_json::Value) -> Result<serde_json::Value> {
    ...
}
    }

    /// A tool that always fails.
    struct FailTool;

    #[async_trait]
    impl crate::tool_registry::AgentTool for FailTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, _params: serde_json::Value) -> Result<serde_json::Value> {
    ...
}
    }

    /// Mock provider returning N tool calls on the first call, then text.
    struct MultiToolProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for MultiToolProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_parallel_tool_execution() {
    ...
}

    #[tokio::test]
    async fn test_parallel_tool_one_fails() {
    ...
}

    #[tokio::test]
    async fn test_parallel_execution_is_concurrent() {
    ...
}

    // ── sanitize_tool_result tests ──────────────────────────────────

    #[test]
    fn test_sanitize_short_input_unchanged() {
    ...
}

    #[test]
    fn test_sanitize_truncates_long_input() {
    ...
}

    #[test]
    fn test_sanitize_truncate_respects_char_boundary() {
    ...
}

    #[test]
    fn test_sanitize_strips_base64_data_uri() {
    ...
}

    #[test]
    fn test_sanitize_preserves_short_base64() {
    ...
}

    #[test]
    fn test_sanitize_strips_long_hex() {
    ...
}

    #[test]
    fn test_sanitize_preserves_short_hex() {
    ...
}

    // ── extract_images_from_text tests ───────────────────────────────

    #[test]
    fn test_extract_images_basic() {
    ...
}

    #[test]
    fn test_extract_images_jpeg() {
    ...
}

    #[test]
    fn test_extract_images_multiple() {
    ...
}

    #[test]
    fn test_extract_images_ignores_non_image() {
    ...
}

    #[test]
    fn test_extract_images_ignores_short_payload() {
    ...
}

    // ── tool_result_to_content tests ─────────────────────────────────

    #[test]
    fn test_tool_result_to_content_no_vision() {
    ...
}

    #[test]
    fn test_tool_result_to_content_with_vision() {
    ...
}

    #[test]
    fn test_tool_result_to_content_vision_no_images() {
    ...
}

    #[test]
    fn test_tool_result_to_content_vision_only_image() {
    ...
}

    // ── Vision Provider Integration Tests ─────────────────────────────

    /// Mock provider that supports vision.
    struct VisionEnabledProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for VisionEnabledProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        fn supports_vision(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    /// Tool that returns a result with an embedded screenshot
    struct ScreenshotTool;

    #[async_trait]
    impl crate::tool_registry::AgentTool for ScreenshotTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, _params: serde_json::Value) -> Result<serde_json::Value> {
    ...
}
    }

    #[tokio::test]
    async fn test_vision_provider_tool_result_sanitized() {
    ...
}

    #[tokio::test]
    async fn test_tool_call_end_event_contains_raw_result() {
    ...
}

    // ── Extract Images Edge Cases ─────────────────────────────────────

    #[test]
    fn test_extract_images_webp() {
    ...
}

    #[test]
    fn test_extract_images_gif() {
    ...
}

    #[test]
    fn test_extract_images_with_special_base64_chars() {
    ...
}

    #[test]
    fn test_extract_images_preserves_surrounding_text() {
    ...
}

    #[test]
    fn test_extract_images_in_json_context() {
    ...
}

    // ── Tool Result Content Format Tests ──────────────────────────────

    #[test]
    fn test_tool_result_to_content_openai_format() {
    ...
}

    #[test]
    fn test_tool_result_to_content_truncation() {
    ...
}

    /// Native streaming provider that emits XML-like function text instead of
    /// structured tool events on the first pass.
    struct NativeTextFunctionStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for NativeTextFunctionStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_streaming_native_text_function_tool_calling() {
    ...
}

    /// Streaming provider that returns plain text only (no tool calls) on
    /// an explicit `/sh` prompt. Runner should force an exec call on iteration 1.
    struct DirectCommandNoToolStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for DirectCommandNoToolStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_explicit_sh_command_forces_exec_streaming() {
    ...
}

    struct PlainTextOnlyStreamProvider;

    #[async_trait]
    impl LlmProvider for PlainTextOnlyStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_unprefixed_command_like_text_does_not_force_exec_streaming() {
    ...
}

    struct ReasoningThenAnswerStreamProvider;

    #[async_trait]
    impl LlmProvider for ReasoningThenAnswerStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_streaming_reasoning_not_in_final_text() {
    ...
}

    // ── Streaming tool-call index mapping tests ─────────────────────

    /// Mock streaming provider that emits text + a tool call at a non-zero
    /// streaming index. This simulates GitHub Copilot proxying Anthropic
    /// where the text content block is at index 0 and the tool_use block
    /// is at index 1.
    ///
    /// On the first call it streams text + tool call (index 1).
    /// On the second call it streams a final text response.
    struct NonZeroIndexStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for NonZeroIndexStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            _messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    /// Regression test: when a streaming provider emits a tool call with a
    /// non-zero index (e.g. index 1 because index 0 is a text block), the
    /// runner must still correctly assemble the tool call arguments.
    ///
    /// Before the fix, the finalization code used the streaming index as the
    /// vec position directly: `tool_calls[1]` when `tool_calls.len() == 1`,
    /// silently dropping the arguments.
    #[tokio::test]
    async fn test_streaming_nonzero_tool_call_index_preserves_args() {
    ...
}

    /// Similar to the above, but with TWO tool calls at non-zero indices
    /// (e.g. index 2 and 4 with text blocks in between) to ensure the
    /// mapping handles multiple non-contiguous indices.
    struct MultiNonZeroIndexStreamProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for MultiNonZeroIndexStreamProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            _messages: Vec<ChatMessage>,
            _tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_streaming_multiple_nonzero_indices() {
    ...
}

    // ── Retry tests ─────────────────────────────────────────────────

    #[test]
    fn test_is_retryable_server_error() {
    ...
}

    #[test]
    fn test_is_rate_limit_error() {
    ...
}

    #[test]
    fn test_is_billing_quota_error() {
    ...
}

    #[test]
    fn test_next_retry_delay_skips_billing_quota_errors() {
    ...
}

    #[test]
    fn test_extract_retry_after_ms() {
    ...
}

    #[test]
    fn test_next_rate_limit_retry_ms_doubles_and_caps() {
    ...
}

    /// Provider that fails with a 500 on the first call, succeeds on the second.
    struct TransientFailProvider {
    ...
}

    /// Provider that fails with 429 for the first N calls, then succeeds.
    struct RateLimitFailProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for TransientFailProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[async_trait]
    impl LlmProvider for RateLimitFailProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn test_retry_on_transient_error_non_streaming() {
    ...
}

    #[tokio::test]
    async fn test_retry_on_transient_error_streaming() {
    ...
}

    #[tokio::test]
    async fn test_retry_on_rate_limit_non_streaming() {
    ...
}

    #[tokio::test]
    async fn test_retry_on_rate_limit_streaming() {
    ...
}

    // ── sanitize_tool_name ────────────────────────────────────────────

    #[test]
    fn sanitize_tool_name_clean_input() {
    ...
}

    #[test]
    fn sanitize_tool_name_trims_whitespace() {
    ...
}

    #[test]
    fn sanitize_tool_name_strips_quotes() {
    ...
}

    #[test]
    fn sanitize_tool_name_partial_quotes_unchanged() {
    ...
}

    /// All real tool names used in production must survive sanitization unchanged.
    #[test]
    fn sanitize_tool_name_noop_on_real_tool_names() {
    ...
}

    #[test]
    fn sanitize_tool_name_empty_string() {
    ...
}

    #[test]
    fn sanitize_tool_name_only_quotes() {
    ...
}

    #[test]
    fn sanitize_tool_name_preserves_internal_quotes() {
    ...
}

    #[test]
    fn sanitize_tool_name_single_quotes_not_stripped() {
    ...
}
}
