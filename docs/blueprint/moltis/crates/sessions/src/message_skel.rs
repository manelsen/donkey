//! Typed message structures for session storage.
//!
//! These types represent the JSON format stored in session JSONL files.
//! They include both LLM-relevant fields (role, content) and metadata
//! fields (created_at, model, provider, tokens, channel).

use serde::{Deserialize, Serialize};

/// A message stored in a session JSONL file.
///
/// Includes both the LLM-relevant content and metadata for UI display
/// and analytics. The `role` field determines which variant this is.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "role", rename_all = "lowercase")]
pub enum PersistedMessage {
    ...
}

/// User message content: plain text or multimodal array.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum MessageContent {
    ...
}

/// A single block in multimodal content.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentBlock {
    ...
}

/// Image URL data (for multimodal content).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageUrl {
    ...
}

/// A tool call stored in an assistant message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersistedToolCall {
    ...
}

/// Function details in a tool call.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersistedFunction {
    ...
}

impl PersistedMessage {
    /// Create a user message with plain text content.
    pub fn user(text: impl Into<String>) -> Self {

    /// Create a user message with plain text and channel metadata.
    pub fn user_with_channel(text: impl Into<String>, channel: serde_json::Value) -> Self {
    ...
}

    /// Create a user message with multimodal content.
    pub fn user_multimodal(blocks: Vec<ContentBlock>) -> Self {
    ...
}

    /// Create a user message with multimodal content and channel metadata.
    pub fn user_multimodal_with_channel(
        blocks: Vec<ContentBlock>,
        channel: serde_json::Value,
    ) -> Self {
    ...
}

    /// Create an assistant message with token usage and model info.
    pub fn assistant(
        text: impl Into<String>,
        model: impl Into<String>,
        provider: impl Into<String>,
        input_tokens: u32,
        output_tokens: u32,
        audio: Option<String>,
    ) -> Self {
    ...
}

    /// Create a system message (e.g., for error display).
    pub fn system(text: impl Into<String>) -> Self {
    ...
}

    /// Create a notice message shown in UI but skipped from model context.
    pub fn notice(text: impl Into<String>) -> Self {
    ...
}

    /// Create a tool result message.
    pub fn tool(tool_call_id: impl Into<String>, content: impl Into<String>) -> Self {
    ...
}

    /// Create a tool execution result message.
    pub fn tool_result(
        tool_call_id: impl Into<String>,
        tool_name: impl Into<String>,
        arguments: Option<serde_json::Value>,
        success: bool,
        result: Option<serde_json::Value>,
        error: Option<String>,
    ) -> Self {
    ...
}

    /// Create a tool execution result message with reasoning text.
    pub fn tool_result_with_reasoning(
        tool_call_id: impl Into<String>,
        tool_name: impl Into<String>,
        arguments: Option<serde_json::Value>,
        success: bool,
        result: Option<serde_json::Value>,
        error: Option<String>,
        reasoning: Option<String>,
    ) -> Self {
    ...
}

    /// Create a tool result message with a run ID linking it to its agent run.
    pub fn tool_result_with_run_id(
        tool_call_id: impl Into<String>,
        tool_name: impl Into<String>,
        arguments: Option<serde_json::Value>,
        success: bool,
        result: Option<serde_json::Value>,
        error: Option<String>,
        run_id: impl Into<String>,
    ) -> Self {
    ...
}

    /// Convert to JSON value for storage.
    ///
    /// This cannot fail because `PersistedMessage` only contains types with
    /// infallible serialization (strings, numbers, booleans, vecs, options).
    #[allow(clippy::expect_used)]
    pub fn to_value(&self) -> serde_json::Value {
    ...
}
}

impl ContentBlock {
    /// Create a text content block.
    pub fn text(text: impl Into<String>) -> Self {

    /// Create an image URL content block from base64 data.
    pub fn image_base64(media_type: &str, data: &str) -> Self {
    ...
}
}

fn now_ms() -> u64 {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn user_multimodal_serializes_correctly() {
    ...
}

    #[test]
    fn assistant_serializes_correctly() {
    ...
}

    #[test]
    fn notice_serializes_correctly() {
    ...
}

    #[test]
    fn user_text_deserializes_correctly() {
    ...
}

    #[test]
    fn user_with_audio_serializes_correctly() {
    ...
}

    #[test]
    fn user_without_audio_field_deserializes() {
    ...
}

    #[test]
    fn user_multimodal_deserializes_correctly() {
    ...
}

    #[test]
    fn roundtrip_user_text() {
    ...
}

    #[test]
    fn roundtrip_notice() {
    ...
}

    #[test]
    fn roundtrip_assistant() {
    ...
}

    #[test]
    fn roundtrip_assistant_with_audio() {
    ...
}

    #[test]
    fn assistant_without_audio_field_deserializes() {
    ...
}

    #[test]
    fn tool_result_serializes_correctly() {
    ...
}

    #[test]
    fn tool_result_error_serializes_correctly() {
    ...
}

    #[test]
    fn roundtrip_tool_result() {
    ...
}

    #[test]
    fn tool_result_deserializes_from_json() {
    ...
}

    #[test]
    fn tool_result_with_reasoning_roundtrips() {
    ...
}

    #[test]
    fn tool_result_without_reasoning_omits_field() {
    ...
}
}
