//! Strip internal XML tags and special tokens from LLM responses.
//!
//! Some models leak internal reasoning tags (`<thinking>`, `<reflection>`, etc.)
//! or special control tokens (`<|eot_id|>`, `<|im_end|>`, etc.) into their
//! responses. This module strips them to produce clean user-facing text.
//!
//! The stripping is done with hand-rolled string scanning (no regex) to match
//! the existing `strip_base64_blobs` pattern in `runner.rs`.

use crate::model::ToolCall;

/// Known internal XML tags that should be stripped from LLM responses.
const INTERNAL_TAGS: &[&str] = &[
    "thinking",
    "think",
    "reflection",
    "inner_monologue",
    "scratchpad",
    "reasoning",
    "analysis",
    "self_reflection",
    "meta",
    "internal_thought",
    "function_call",
    "tool_use",
    "invoke",
    "tool_calls",
];

/// Standalone pipe tokens that should be stripped.
const STANDALONE_PIPE_TOKENS: &[&str] = &[
    "<|eot_id|>",
    "<|end|>",
    "<|im_end|>",
    "<|im_start|>",
    "<|begin_of_text|>",
    "<|end_of_text|>",
    "<|python_tag|>",
    "<|eom_id|>",
    "<|start_header_id|>",
    "<|end_header_id|>",
];

/// Tags used for tool call recovery.
const TOOL_CALL_TAGS: &[&str] = &["function_call", "tool_call"];

/// Main entry point: chain all stripping passes and trim the result.
pub fn clean_response(text: &str) -> String {
    ...
}

/// Strip all known internal XML tags and their content.
fn strip_internal_tags(text: &str) -> String {
    ...
}

/// Strip `<tag ...>content</tag>` pairs, handling optional attributes.
///
/// Matches opening tags with or without attributes (e.g. `<thinking>`,
/// `<thinking type="deep">`), and removes everything up to and including
/// the corresponding closing tag.
fn strip_xml_tag(text: &str, tag: &str) -> String {
    ...
}

/// Strip `<|tag|>...<|/tag|>` pairs (pipe-delimited variant).
fn strip_pipe_tag(text: &str, tag: &str) -> String {
    ...
}

/// Strip standalone pipe tokens (`<|eot_id|>`, `<|im_end|>`, etc.).
fn strip_standalone_pipe_tokens(text: &str) -> String {
    ...
}

/// Strip reasoning pattern blocks: `<Thinking>...</Thinking>` and similar
/// capitalized variants that some models produce at the start of responses.
fn strip_reasoning_patterns(text: &str) -> String {
    ...
}

/// Attempt to recover structured `ToolCall` from `<function_call>` or
/// `<tool_call>` XML blocks embedded in the response text.
///
/// Returns the cleaned text (with recovered blocks removed) and any
/// recovered tool calls.
pub fn recover_tool_calls_from_content(text: &str) -> (String, Vec<ToolCall>) {
    ...
}

/// Parse JSON content from an XML tool call block into a `ToolCall`.
///
/// Accepts formats like:
/// ```json
/// {"name": "exec", "arguments": {"command": "ls"}}
/// ```
/// or:
/// ```json
/// {"tool": "exec", "arguments": {"command": "ls"}}
/// ```
fn parse_tool_call_json(content: &str) -> Option<ToolCall> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn strip_tag_with_attributes() {
    ...
}

    #[test]
    fn strip_multiple_tags() {
    ...
}

    #[test]
    fn no_matching_tag_unchanged() {
    ...
}

    #[test]
    fn unclosed_tag_strips_to_end() {
    ...
}

    #[test]
    fn nested_content_preserved_outside() {
    ...
}

    // ── strip_pipe_tag ─────────────────────────────────────────────

    #[test]
    fn strip_pipe_tag_basic() {
    ...
}

    #[test]
    fn strip_pipe_tag_no_close() {
    ...
}

    // ── strip_standalone_pipe_tokens ───────────────────────────────

    #[test]
    fn strip_eot_tokens() {
    ...
}

    #[test]
    fn strip_multiple_standalone_tokens() {
    ...
}

    // ── strip_reasoning_patterns ───────────────────────────────────

    #[test]
    fn strip_capitalized_thinking() {
    ...
}

    // ── clean_response (integration) ───────────────────────────────

    #[test]
    fn clean_response_strips_all_tag_types() {
    ...
}

    #[test]
    fn clean_response_preserves_normal_text() {
    ...
}

    #[test]
    fn clean_response_trims_whitespace() {
    ...
}

    #[test]
    fn clean_response_complex_mixed() {
    ...
}

    // ── recover_tool_calls_from_content ────────────────────────────

    #[test]
    fn recover_tool_call_from_function_call_block() {
    ...
}

    #[test]
    fn recover_tool_call_with_tool_key() {
    ...
}

    #[test]
    fn recover_no_tool_calls_returns_empty() {
    ...
}

    #[test]
    fn recover_malformed_json_skipped() {
    ...
}

    #[test]
    fn recover_multiple_tool_calls() {
    ...
}

    // ── New INTERNAL_TAGS: invoke, tool_calls ─────────────────────────

    #[test]
    fn clean_response_strips_invoke_tags() {
    ...
}

    #[test]
    fn clean_response_strips_tool_calls_wrapper() {
    ...
}

    #[test]
    fn clean_response_word_invoke_in_prose_preserved() {
    ...
}

    /// Existing tool_call recovery is NOT broken by new INTERNAL_TAGS.
    /// TOOL_CALL_TAGS ("function_call", "tool_call") are separate from INTERNAL_TAGS.
    #[test]
    fn recover_tool_calls_unaffected_by_new_internal_tags() {
    ...
}

    /// clean_response strips leaked <invoke> but does NOT interfere with
    /// proper tool call recovery (which runs separately in the runner).
    #[test]
    fn clean_response_strips_malformed_invoke_leftovers() {
    ...
}
}
