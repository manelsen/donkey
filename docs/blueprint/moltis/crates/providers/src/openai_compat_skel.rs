//! Shared helpers for OpenAI-compatible streaming with tools.
//!
//! This module provides reusable functions for parsing OpenAI-style SSE streams
//! that include tool calls. Used by openai.rs, github_copilot.rs, and kimi_code.rs.

use std::collections::{HashMap, HashSet};

use {serde::Serialize, tracing::trace};

use moltis_agents::model::{
    ChatMessage, CompletionResponse, StreamEvent, ToolCall, Usage, UserContent,
};

// ============================================================================
// OpenAI Tool Schema Types
// ============================================================================
// These types enforce the correct structure for OpenAI-compatible APIs.
// Using typed structs instead of manual JSON prevents missing fields at compile time.
//
// References:
// - Chat Completions: https://platform.openai.com/docs/guides/function-calling
// - Responses API: https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/responses
// ============================================================================

/// Chat Completions API tool format (nested under "function").
///
/// ```json
/// { "type": "function", "function": { "name": "...", ... } }
/// ```
#[derive(Debug, Serialize)]
pub struct ChatCompletionsTool {
    ...
}

/// The function definition nested inside ChatCompletionsTool.
#[derive(Debug, Serialize)]
pub struct ChatCompletionsFunction {
    ...
}

/// Responses API tool format (flat, name at top level).
///
/// ```json
/// { "type": "function", "name": "...", "parameters": {...}, "strict": true }
/// ```
#[derive(Debug, Serialize)]
pub struct ResponsesApiTool {
    ...
}

/// Make a JSON Schema node nullable by adding `"null"` to its type.
///
/// For schemas using `"type": "string"` (or any single type), this converts to
/// `"type": ["string", "null"]`.  For schemas using `anyOf`/`oneOf`, it appends
/// a `{"type": "null"}` variant.  Already-nullable schemas are left unchanged.
fn make_nullable(schema: &mut serde_json::Value) {
    ...
}

/// Recursively patch schema for OpenAI strict mode compliance.
///
/// OpenAI's strict mode requires:
/// 1. `additionalProperties: false` on every object in the schema tree
/// 2. All properties must be listed in the `required` array
///
/// Properties not in the original `required` array are made nullable so the
/// model can send `null` for unused optional fields instead of fabricating
/// placeholder values.
///
/// This function recursively patches nested objects in `properties`, array
/// `items`, `anyOf`/`oneOf`/`allOf` variants, etc.
pub fn patch_schema_for_strict_mode(schema: &mut serde_json::Value) {
    ...
}

/// Convert tool schemas to OpenAI Chat Completions function-calling format.
///
/// Uses the nested `function` object format required by Chat Completions API:
/// ```json
/// { "type": "function", "function": { "name": "...", ... } }
/// ```
///
/// Adds `strict: true` and patches schemas for strict mode compliance:
/// - `additionalProperties: false` on all object schemas
/// - All properties included in `required` array
///
/// This is required by some APIs (Claude via Copilot) to ensure the model
/// provides all required fields.
///
/// See: <https://platform.openai.com/docs/guides/function-calling>
pub fn to_openai_tools(tools: &[serde_json::Value]) -> Vec<serde_json::Value> {
    ...
}

/// Convert tool schemas to OpenAI Responses API function-calling format.
///
/// Uses the flat format required by the Responses API where `name` is at top level:
/// ```json
/// { "type": "function", "name": "...", "parameters": {...}, "strict": true }
/// ```
///
/// This is the format used by OpenAI Codex and the Responses API.
///
/// Patches schemas for strict mode compliance:
/// - `additionalProperties: false` on all object schemas
/// - All properties included in `required` array
///
/// See: <https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/responses>
pub fn to_responses_api_tools(tools: &[serde_json::Value]) -> Vec<serde_json::Value> {
    ...
}

/// Convert typed chat messages to Responses API input items.
///
/// Responses API accepts a heterogeneous input array (messages, tool calls, and
/// tool outputs). This keeps one canonical conversion for providers that use
/// Responses transport (SSE or WebSocket).
#[must_use]
pub fn to_responses_input(messages: &[ChatMessage]) -> Vec<serde_json::Value> {
    ...
}

/// Parse tool_calls from an OpenAI response message (non-streaming).
pub fn parse_tool_calls(message: &serde_json::Value) -> Vec<ToolCall> {
    ...
}

fn usage_value_at_path(usage: &serde_json::Value, path: &[&str]) -> Option<u64> {
    ...
}

fn usage_field_u32(usage: &serde_json::Value, paths: &[&[&str]]) -> u32 {
    ...
}

fn usage_object_from_payload(payload: &serde_json::Value) -> Option<&serde_json::Value> {
    ...
}

/// Parse usage payloads from OpenAI-compatible backends.
///
/// Different providers use different field names:
/// - OpenAI-style: `prompt_tokens`, `completion_tokens`
/// - Anthropic/MiniMax-style: `input_tokens`, `output_tokens`
/// - Cache fields may be top-level or nested in `*_tokens_details`.
#[must_use]
pub fn parse_openai_compat_usage(usage: &serde_json::Value) -> Usage {
    ...
}

/// Parse usage from an OpenAI-compatible payload, checking common nesting variants.
///
/// Providers differ on where they place usage metadata:
/// - top-level `usage`
/// - `choices[0].usage`
/// - `choices[0].delta.usage`
/// - `choices[0].message.usage`
/// - provider extension blocks (for example `x_groq.usage`)
#[must_use]
pub fn parse_openai_compat_usage_from_payload(payload: &serde_json::Value) -> Option<Usage> {
    ...
}

/// Strip `<think>...</think>` tags from content, returning `(visible, thinking)`.
///
/// Models like DeepSeek R1, QwQ, and MiniMax embed chain-of-thought reasoning
/// inside `<think>` tags in the `content` field rather than using a separate
/// `reasoning_content` field.  This helper splits content into the visible
/// answer text and the thinking text so callers can handle them appropriately.
///
/// Edge cases handled:
/// - Multiple `<think>` blocks interspersed with answer text
/// - Unclosed `<think>` tag (remainder treated as reasoning)
/// - Empty `<think></think>` blocks
/// - Nested angle brackets inside thinking text
pub fn strip_think_tags(content: &str) -> (String, String) {
    ...
}

/// State for tracking streaming tool calls.
#[derive(Default)]
pub struct StreamingToolState {
    ...
}

/// Result of processing a single SSE line.
pub enum SseLineResult {
    ...
}

/// Emit a `ReasoningDelta`, stripping leading whitespace at the start of a
/// think block so the UI doesn't show a blank prefix.
fn emit_reasoning(text: String, strip_leading_ws: &mut bool, events: &mut Vec<StreamEvent>) {
    ...
}

/// Emit a visible `Delta`, stripping leading whitespace after a `</think>`
/// block so the UI doesn't show blank lines before the answer.
fn emit_visible(text: String, strip_leading_ws: &mut bool, events: &mut Vec<StreamEvent>) {
    ...
}

/// Process streamed content through the `<think>` tag state machine.
///
/// Content arriving inside `<think>...</think>` is emitted as
/// `ReasoningDelta`; content outside is emitted as `Delta`.
/// Tags may be split across SSE chunks — `tag_buffer` accumulates
/// partial tag fragments until they can be resolved.
/// Leading whitespace at the start of each think block is stripped.
fn process_content_think_tags(
    content: &str,
    state: &mut StreamingToolState,
    events: &mut Vec<StreamEvent>,
) {
    ...
}

/// Return the length of the longest suffix of `text` that is a prefix of `tag`.
///
/// For example, `longest_tag_suffix("abc<th", "<think>")` returns 3 because
/// `"<th"` is a 3-character prefix of `"<think>"`.
fn longest_tag_suffix(text: &str, tag: &str) -> usize {
    ...
}

/// Process a single SSE data line and return any events to yield.
///
/// This handles the common OpenAI streaming format used by:
/// - OpenAI API
/// - GitHub Copilot API
/// - Kimi Code API
/// - Any other OpenAI-compatible API
///
/// Content inside `<think>...</think>` tags is emitted as `ReasoningDelta`
/// events rather than `Delta`, allowing the UI to show reasoning text
/// separately. This handles models (DeepSeek R1, QwQ, MiniMax) that embed
/// chain-of-thought in `content` rather than using `reasoning_content`.
pub fn process_openai_sse_line(data: &str, state: &mut StreamingToolState) -> SseLineResult {
    ...
}

/// Generate the final events when stream ends (tool call completions + done).
///
/// Any residual content in the think-tag buffer is flushed as the appropriate
/// event type (reasoning if we were inside a think block, visible otherwise).
pub fn finalize_stream(state: &mut StreamingToolState) -> Vec<StreamEvent> {
    ...
}

// ============================================================================
// Responses API helpers (shared by openai.rs and github_copilot.rs)
// ============================================================================

/// Split system messages into `instructions` and convert the rest to Responses
/// API `input` items.
///
/// The Responses API uses a top-level `instructions` field instead of a system
/// message role.  This function extracts all system messages, joins them with
/// `\n\n`, and converts the remaining messages via [`to_responses_input`].
#[must_use]
pub fn split_responses_instructions_and_input(
    messages: Vec<ChatMessage>,
) -> (Option<String>, Vec<serde_json::Value>) {
    ...
}

/// Resolve the output index from a Responses API event.
///
/// The Responses API uses `output_index` for items and `index` for
/// sub-item fields.  WebSocket events may also use `item_index`.
/// Falls back to `fallback` if none of these keys are present.
pub fn responses_output_index(event: &serde_json::Value, fallback: usize) -> usize {
    ...
}

/// State for tracking Responses API SSE streaming.
#[derive(Default)]
pub struct ResponsesStreamState {
    ...
}

/// Process a single SSE data line from a Responses API stream.
///
/// Returns [`SseLineResult`] indicating whether to skip, yield events, or stop.
///
/// Handles the event types emitted by the Responses API:
/// - `response.output_text.delta` → text delta
/// - `response.output_item.added` (type=function_call) → tool call start
/// - `response.function_call_arguments.delta` → tool call arguments delta
/// - `response.function_call_arguments.done` → tool call complete
/// - `response.completed` → parse usage, done
/// - `error` / `response.failed` → error
pub fn process_responses_sse_line(data: &str, state: &mut ResponsesStreamState) -> SseLineResult {
    ...
}

/// Generate the final events when a Responses API stream ends.
///
/// Emits `ToolCallComplete` for any pending tool calls and a final `Done` with
/// accumulated usage.
pub fn finalize_responses_stream(state: &mut ResponsesStreamState) -> Vec<StreamEvent> {
    ...
}

/// Parse a non-streaming Responses API JSON response into [`CompletionResponse`].
///
/// The Responses API returns an `output` array containing `message` items
/// (with `content[].text`) and `function_call` items (with `call_id`, `name`,
/// `arguments`).
pub fn parse_responses_completion(resp: &serde_json::Value) -> CompletionResponse {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_to_openai_tools_nested_objects() {
    ...
}

    #[test]
    fn test_to_openai_tools_array_items() {
    ...
}

    #[test]
    fn test_to_openai_tools_anyof() {
    ...
}

    #[test]
    fn test_to_openai_tools_all_properties_required_and_optional_nullable() {
    ...
}

    #[test]
    fn test_strict_mode_no_required_field_all_become_nullable() {
    ...
}

    #[test]
    fn test_strict_mode_already_nullable_not_doubled() {
    ...
}

    #[test]
    fn test_to_openai_tools_empty() {
    ...
}

    #[test]
    fn test_parse_tool_calls_empty() {
    ...
}

    #[test]
    fn test_parse_tool_calls_with_calls() {
    ...
}

    #[test]
    fn test_parse_openai_compat_usage_openai_fields() {
    ...
}

    #[test]
    fn test_parse_openai_compat_usage_input_output_fields() {
    ...
}

    #[test]
    fn test_parse_openai_compat_usage_camel_case_string_fields() {
    ...
}

    #[test]
    fn test_parse_openai_compat_usage_from_payload_choice_usage() {
    ...
}

    #[test]
    fn test_parse_openai_compat_usage_from_payload_delta_usage() {
    ...
}

    #[test]
    fn test_process_sse_usage_chunk_with_input_output_fields() {
    ...
}

    #[test]
    fn test_process_sse_usage_chunk_with_choice_nested_usage() {
    ...
}

    #[test]
    fn test_process_sse_done() {
    ...
}

    #[test]
    fn test_process_sse_text_delta() {
    ...
}

    #[test]
    fn test_process_sse_reasoning_content_delta() {
    ...
}

    #[test]
    fn test_process_sse_reasoning_delta_openrouter() {
    ...
}

    #[test]
    fn test_process_sse_tool_call_start() {
    ...
}

    #[test]
    fn test_process_sse_tool_call_args_delta() {
    ...
}