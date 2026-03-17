//! Text-based tool call parsing for models without native tool calling.
//!
//! Extracts structured `ToolCall` values from free-form LLM text output.
//! Supports multiple formats:
//!
//! 1. **Fenced blocks**: `` ```tool_call\n{...}\n``` ``
//! 2. **XML function calls**: `<function=name><parameter=key>value</parameter></function>`
//! 3. **Bare JSON**: `{"tool": "name", "arguments": {...}}`

use std::fmt::Write;

use crate::{json_repair, model::ToolCall};

/// Maximum length for synthetic tool call IDs (OpenAI compatibility).
const SYNTHETIC_TOOL_CALL_ID_MAX_LEN: usize = 40;

/// Generate a synthetic tool-call ID that is OpenAI-compatible (max 40 chars).
pub(crate) fn new_synthetic_tool_call_id(prefix: &str) -> String {
    ...
}

/// Result of parsing a single tool call block from text.
struct ParsedBlock {
    ...
}

/// Parse ALL tool call blocks from model text output.
///
/// Returns a list of parsed `ToolCall` values and any remaining text that was
/// not part of a tool call block (interstitial commentary, reasoning, etc.).
///
/// Tries parsers in priority order: fenced, XML function, bare JSON.
pub fn parse_tool_calls_from_text(text: &str) -> (Vec<ToolCall>, Option<String>) {
    ...
}

/// Backward-compatible single tool call parser.
///
/// Wraps [`parse_tool_calls_from_text`] and returns only the first match.
pub fn parse_tool_call_from_text(text: &str) -> Option<(ToolCall, Option<String>)> {
    ...
}

/// Heuristic: does the text look like it was *trying* to make a tool call but
/// failed to produce valid output?
pub fn looks_like_failed_tool_call(text: &Option<String>) -> bool {
    ...
}

// ── Fenced block parser ─────────────────────────────────────────────────────

fn collect_fenced_blocks(text: &str, blocks: &mut Vec<ParsedBlock>) {
    ...
}

// ── XML function parser ─────────────────────────────────────────────────────

fn collect_function_blocks(text: &str, blocks: &mut Vec<ParsedBlock>) {
    ...
}

// ── XML <invoke> parser ─────────────────────────────────────────────────────

/// Extract the value of a named attribute from an XML attribute string.
/// E.g. `extract_xml_attr(r#"name="exec" id="1""#, "name")` → `Some("exec")`.
fn extract_xml_attr<'a>(attr_str: &'a str, attr_name: &str) -> Option<&'a str> {
    let needle = format!("{attr_name}=\"");
    let start = attr_str.find(&needle)?;
    let value_start = start + needle.len();
    let rest = attr_str.get(value_start..)?;
    let end = rest.find('"')?;
    Some(&rest[..end])
}

/// Collect `<invoke name="tool"><arg name="key">value</arg></invoke>` blocks.
fn collect_invoke_blocks(text: &str, blocks: &mut Vec<ParsedBlock>) {
    ...
}

// ── Bare JSON parser ────────────────────────────────────────────────────────

fn collect_bare_json_blocks(text: &str, blocks: &mut Vec<ParsedBlock>) {
    ...
}