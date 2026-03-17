//! Typed multimodal content structures for LLM providers.
//!
//! This module provides strongly-typed data structures for multimodal content
//! (text + images) that can be sent to various LLM providers. Using typed structs
//! instead of raw JSON prevents missing fields at compile time and documents the
//! expected API formats.
//!
//! References:
//! - OpenAI: <https://platform.openai.com/docs/guides/vision>
//! - Anthropic: <https://docs.anthropic.com/claude/docs/vision>
//! - Gemini: <https://ai.google.dev/gemini-api/docs/vision>

use serde::{Deserialize, Serialize};

// ============================================================================
// OpenAI Multimodal Types (Chat Completions API)
// ============================================================================

/// Content block for OpenAI multimodal messages.
///
/// OpenAI uses a discriminated union with `type` field:
/// ```json
/// { "type": "text", "text": "..." }
/// { "type": "image_url", "image_url": { "url": "data:image/png;base64,..." } }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum OpenAiContent {
    ...
}

/// Image URL details for OpenAI vision.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OpenAiImageUrl {
    ...
}

impl OpenAiContent {
    /// Create a text content block.
    pub fn text(text: impl Into<String>) -> Self {

    /// Create an image URL content block from a data URI.
    pub fn image_data_uri(data_uri: impl Into<String>) -> Self {
    ...
}

    /// Create an image URL content block with detail level.
    pub fn image_with_detail(url: impl Into<String>, detail: impl Into<String>) -> Self {
    ...
}
}

// ============================================================================
// Anthropic Multimodal Types (Messages API)
// ============================================================================

/// Content block for Anthropic multimodal messages.
///
/// Anthropic uses a discriminated union with `type` field:
/// ```json
/// { "type": "text", "text": "..." }
/// { "type": "image", "source": { "type": "base64", "media_type": "image/png", "data": "..." } }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AnthropicContent {
    ...
}

/// Image source for Anthropic vision.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AnthropicImageSource {
    ...
}

impl AnthropicContent {
    /// Create a text content block.
    pub fn text(text: impl Into<String>) -> Self {

    /// Create an image content block from base64 data.
    pub fn image_base64(media_type: impl Into<String>, data: impl Into<String>) -> Self {
    ...
}
}

// ============================================================================
// Tool Result Content Types
// ============================================================================

/// Tool result content that can be either plain text or multimodal.
///
/// Most LLM APIs expect tool results to be strings. For vision-capable models,
/// we *could* send multimodal content, but currently most APIs don't support
/// images in tool results (only in user messages).
///
/// This enum documents the possible formats for future use.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum ToolResultContent {
    ...
}

impl ToolResultContent {
    /// Create a plain text tool result.
    pub fn text(s: impl Into<String>) -> Self {

    /// Create an OpenAI-style multimodal tool result.
    pub fn openai_multimodal(blocks: Vec<OpenAiContent>) -> Self {
    ...
}

    /// Create an Anthropic-style multimodal tool result.
    pub fn anthropic_multimodal(blocks: Vec<AnthropicContent>) -> Self {
    ...
}
}

// ============================================================================
// Conversion Helpers
// ============================================================================

/// Parse a data URI into its components.
///
/// Returns `Some((media_type, data))` for valid data URIs like:
/// - `data:image/png;base64,iVBORw0KGgo...`
/// - `data:image/jpeg;base64,/9j/4AAQ...`
///
/// Returns `None` for invalid or non-base64 data URIs.
pub fn parse_data_uri(uri: &str) -> Option<(&str, &str)> {
    ...
}

/// Build a data URI from media type and base64 data.
pub fn build_data_uri(media_type: &str, data: &str) -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn openai_image_content_serializes_correctly() {
    ...
}

    #[test]
    fn openai_image_with_detail_serializes_correctly() {
    ...
}

    #[test]
    fn openai_content_deserializes_text() {
    ...
}

    #[test]
    fn openai_content_deserializes_image() {
    ...
}

    #[test]
    fn openai_multimodal_message_format() {
    ...
}

    // ── Anthropic Content Tests ────────────────────────────────────────

    #[test]
    fn anthropic_text_content_serializes_correctly() {
    ...
}

    #[test]
    fn anthropic_image_content_serializes_correctly() {
    ...
}

    #[test]
    fn anthropic_content_deserializes_text() {
    ...
}

    #[test]
    fn anthropic_content_deserializes_image() {
    ...
}

    #[test]
    fn anthropic_multimodal_message_format() {
    ...
}

    // ── Tool Result Content Tests ──────────────────────────────────────

    #[test]
    fn tool_result_text_serializes_as_string() {
    ...
}

    #[test]
    fn tool_result_openai_multimodal_serializes_as_array() {
    ...
}

    #[test]
    fn tool_result_anthropic_multimodal_serializes_as_array() {
    ...
}

    // ── Data URI Parsing Tests ─────────────────────────────────────────

    #[test]
    fn parse_data_uri_png() {
    ...
}

    #[test]
    fn parse_data_uri_jpeg() {
    ...
}

    #[test]
    fn parse_data_uri_webp() {
    ...
}

    #[test]
    fn parse_data_uri_invalid() {
    ...
}

    #[test]
    fn build_data_uri_roundtrip() {
    ...
}

    // ── Provider Format Compatibility Tests ────────────────────────────

    #[test]
    fn openai_format_matches_api_spec() {
    ...
}

    #[test]
    fn anthropic_format_matches_api_spec() {
    ...
}

    // ── Edge Case Tests ────────────────────────────────────────────────

    #[test]
    fn empty_multimodal_content_arrays() {
    ...
}

    #[test]
    fn text_only_multimodal_content() {
    ...
}

    #[test]
    fn image_only_multimodal_content() {
    ...
}

    #[test]
    fn special_characters_in_text() {
    ...
}

    #[test]
    fn large_base64_data() {
    ...
}
}
