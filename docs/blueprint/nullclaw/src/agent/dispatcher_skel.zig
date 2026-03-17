const std = @import("std");
const providers = @import("../providers/root.zig");

// ═══════════════════════════════════════════════════════════════════════════
// Dispatcher — tool call parsing and result formatting
// ═══════════════════════════════════════════════════════════════════════════

/// A parsed tool call extracted from an LLM response.
pub const ParsedToolCall = struct {
    /// Raw JSON arguments string.
    /// Optional tool_call_id for native tool-calling APIs.

/// Result of parsing tool calls from an LLM response: text content and extracted calls.
pub const ParseResult = struct {

    var out: std.ArrayListUnmanaged(u8) = .empty;

    var remaining = input;
        const after_open = remaining[open_idx..];
        const content_start = open_idx + open_end_rel + 1;
        const after_content = remaining[content_start..];


pub fn stripToolResultMarkup(allocator: std.mem.Allocator, input: []const u8) ![]u8

/// Result of executing a single tool.
pub const ToolExecutionResult = struct {

/// Parse tool calls from an LLM response.
///
/// Two parsing paths (matching ZeroClaw's Rust implementation):
/// 1. First, try parsing as OpenAI native JSON format `{"tool_calls": [...]}`
/// 2. Fall back to XML `<tool_call>` tag parsing
///
/// Returns text portions (joined by newline) and extracted tool calls.
    // First: try OpenAI native JSON format {"tool_calls": [...]}
        const native = parseNativeToolCalls(allocator, response) catch null;
            // No calls found in native format — free and fall through to XML
    // Second: fall back to XML <tool_call> tag parsing

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool

/// Detect whether the response contains explicit tool-call markup tags.
/// Used by the agent loop to avoid leaking raw tool XML-like payloads to users
/// when parsing fails on malformed inner content.
pub fn containsToolCallMarkup(text: []const u8) bool

/// Parse tool calls from an LLM response using XML-style `<tool_call>` tags.
///
/// Expected format:
/// ```
/// Some text
/// <tool_call>
/// {"name": "shell", "arguments": {"command": "ls"}}
/// </tool_call>
/// More text
/// ```
///
/// Returns text portions (joined by newline) and extracted tool calls.
///
/// SECURITY: This function only extracts JSON from within explicit `<tool_call>` tags.
/// It does NOT parse raw JSON from the response body, which prevents prompt injection
/// where malicious content could include JSON mimicking a tool call.
    var text_parts: std.ArrayListUnmanaged([]const u8) = .empty;

    var calls: std.ArrayListUnmanaged(ParsedToolCall) = .empty;

    var remaining = response;

        // Find next tool call marker: either <tool_call> or [TOOL_CALL] or [tool_call]
            const xml_start = std.mem.indexOf(u8, remaining, "<tool_call>");
            const br_start_upper = std.mem.indexOf(u8, remaining, "[TOOL_CALL]");
            const br_start_lower = std.mem.indexOf(u8, remaining, "[tool_call]");

            var best_start: ?usize = null;
            var open_c: u8 = '<';
            var close_c: u8 = '>';
            const marker_len: usize = 11;



        const info = marker_info.?;
        const start = info.start;

        const after_open = remaining[info.end..];
        // Flexible closing tag:
        // 1) Prefer tags whose name contains "tool_call"
        // 2) Fallback to the first closing tag (handles malformed outputs like </arg_value>)
        var strict_end: ?usize = null;
        var strict_end_tag_len: usize = 0;
        var fallback_first_end: ?usize = null;
        var fallback_first_end_tag_len: usize = 0;
        var fallback_last_end: ?usize = null;
        var fallback_last_end_tag_len: usize = 0;
        var search_idx: usize = 0;
            const next_open = std.mem.indexOfScalar(u8, after_open[search_idx..], info.open_char) orelse break;
            const abs_open = search_idx + next_open;
                    const abs_close = abs_open + rel_close;
                    const tag_content = after_open[abs_open + 2 .. abs_close];

        const found_end = strict_end orelse fallback_first_end;
        var end_tag_len = if (strict_end != null) strict_end_tag_len else fallback_first_end_tag_len;

            // Text before the tag
            const before = std.mem.trim(u8, remaining[0..start], " \t\r\n");

            var selected_end = end;
            var parsed_call: ?ParsedToolCall = null;

            // If we only have malformed close-tags (no strict </tool_call>),
            // prefer the last close-tag first. This avoids truncating when JSON
            // arguments contain an early `</...>` string (e.g. HTML content).
                        const last_inner = std.mem.trim(u8, after_open[0..last_end], " \t\r\n");

                const inner = std.mem.trim(u8, after_open[0..selected_end], " \t\r\n");


            // Unclosed tag — attempt conservative recovery for compact calls emitted at
            // end-of-message (e.g. <tool_call>memory_list{"limit":10}).
            const inner_unclosed = std.mem.trim(u8, after_open, " \t\r\n");
            var recovered = false;

                        const before = std.mem.trim(u8, remaining[0..start], " \t\r\n");

                        const before = std.mem.trim(u8, remaining[0..start], " \t\r\n");

                const unresolved = std.mem.trim(u8, remaining, " \t\r\n");


    // Remaining text after last tool call
    const trailing = std.mem.trim(u8, remaining, " \t\r\n");

    // Join text parts

        const sanitized_text = try stripToolResultMarkup(allocator, text);


/// Format tool execution results as XML for the next LLM turn.
pub fn formatToolResults(allocator: std.mem.Allocator, results: []const ToolExecutionResult) ![]const u8

// ═══════════════════════════════════════════════════════════════════════════
// Structured Tool Call Conversion
// ═══════════════════════════════════════════════════════════════════════════

const ToolCall = providers.ToolCall;

/// Convert structured tool calls from a ChatResponse (provider-native format)
/// into ParsedToolCall slices for the agent loop.
///
/// This bridges the provider's `ToolCall` type (id, name, arguments) to the
/// dispatcher's `ParsedToolCall` type used for tool execution.
    var calls: std.ArrayListUnmanaged(ParsedToolCall) = .empty;




// ═══════════════════════════════════════════════════════════════════════════
// Native Tool Dispatcher — OpenAI-format tool_calls support
// ═══════════════════════════════════════════════════════════════════════════

/// Dispatcher format kind.
pub const DispatcherKind = enum {

/// Quick check whether a response string looks like OpenAI native JSON format.
/// Returns true if the text starts with `{` (after trimming whitespace) and contains `"tool_calls"`.
/// This is a lightweight heuristic — full JSON parsing happens in parseNativeToolCalls.
pub fn isNativeJsonFormat(text: []const u8) bool

/// Parse a JSON tool call object: {"name": "...", "arguments": {...}}
/// Tries to parse as-is first, then applies JSON repair as fallback.
fn parseToolCallJson(allocator: std.mem.Allocator, json_str: []const u8) !ParsedToolCall

fn parseToolCallJsonInner(allocator: std.mem.Allocator, parsed: std.json.Parsed(std.json.Value)) !ParsedToolCall

test "extractJsonObject unmatched close bracket does not panic" {
    // Input starts with ']' — no matching open.
    const result = extractJsonObject("] some text [1,2,3]");

test "extractJsonObject with leading text" {
    const input = "Here is the result:{

test "extractJsonObject deeply nested" {
    const input = "{

test "extractJsonObject with string containing braces" {
    const input = "{

test "extractJsonObject empty string" {

test "extractJsonObject unmatched brace" {

test "parseToolCalls three consecutive calls" {
    const allocator = std.testing.allocator;
    const result = try parseToolCalls(allocator, response);

test "formatToolResults with tool_call_id" {
    const allocator = std.testing.allocator;
    const formatted = try formatToolResults(allocator, &results);

test "ParsedToolCall default tool_call_id is null" {

test "ToolExecutionResult default tool_call_id is null" {

// ── Function-tag format tests (<function=name><parameter=key>value</parameter></function>) ──

test "parseFunctionTagCall single parameter" {
    const allocator = std.testing.allocator;
    const inner = "<function=shell><parameter=command>ps aux | grep nullclaw</parameter></function>";
    const call = try parseFunctionTagCall(allocator, inner);

test "parseFunctionTagCall multiple parameters" {
    const allocator = std.testing.allocator;
    const inner = "<function=file_write><parameter=path>/tmp/test.txt</parameter><parameter=content>hello world</parameter></function>";
    const call = try parseFunctionTagCall(allocator, inner);

test "parseFunctionTagCall with whitespace and newlines" {
    const allocator = std.testing.allocator;
    const call = try parseFunctionTagCall(allocator, inner);

test "parseFunctionTagCall no function tag returns error" {
    const allocator = std.testing.allocator;

test "parseToolCalls handles function-tag format inside tool_call" {
    const allocator = std.testing.allocator;
    const result = try parseToolCalls(allocator, response);

test "parseToolCalls function-tag with surrounding text" {
    const allocator = std.testing.allocator;
    const result = try parseToolCalls(allocator, response);

test "parseFunctionTagCall value with quotes is JSON-escaped" {
    const allocator = std.testing.allocator;
    const inner = "<function=shell><parameter=command>echo \"hello world\"</parameter></function>";
    const call = try parseFunctionTagCall(allocator, inner);
    // Verify the JSON is valid by parsing it
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, call.arguments_json, .{

// ── Native tool dispatcher tests ────────────────────────────────

test "isNativeFormat detects OpenAI tool_calls" {

test "isNativeFormat rejects XML format" {
    const xml_response = "Let me check.\n<tool_call>\n{

test "isNativeFormat rejects plain text" {

test "isNativeFormat rejects tool_calls in non-JSON context" {
    // Contains the substring but is not valid JSON

test "parseNativeToolCalls single call" {
    const allocator = std.testing.allocator;

    const result = try parseNativeToolCalls(allocator, response);


test "parseNativeToolCalls multiple calls" {
    const allocator = std.testing.allocator;

    const result = try parseNativeToolCalls(allocator, response);


test "parseNativeToolCalls null content" {
    const allocator = std.testing.allocator;

    const result = try parseNativeToolCalls(allocator, response);


test "parseNativeToolCalls no tool_calls key" {
    const allocator = std.testing.allocator;

    const result = try parseNativeToolCalls(allocator, response);


test "parseNativeToolCalls empty tool_calls array" {
    const allocator = std.testing.allocator;

    const result = try parseNativeToolCalls(allocator, response);


test "parseNativeToolCalls skips entries without function field" {
    const allocator = std.testing.allocator;

    const result = try parseNativeToolCalls(allocator, response);


test "parseNativeToolCalls skips entries with empty function name" {
    const allocator = std.testing.allocator;

    const result = try parseNativeToolCalls(allocator, response);


test "parseNativeToolCalls preserves tool_call_id" {
    const allocator = std.testing.allocator;

    const result = try parseNativeToolCalls(allocator, response);


test "formatNativeToolResults single result" {
    const allocator = std.testing.allocator;
    const formatted = try formatNativeToolResults(allocator, &results);

    // Should be valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, formatted, .{

test "formatNativeToolResults multiple results" {
    const allocator = std.testing.allocator;
    const formatted = try formatNativeToolResults(allocator, &results);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, formatted, .{

test "formatNativeToolResults missing tool_call_id defaults to unknown" {
    const allocator = std.testing.allocator;
    const formatted = try formatNativeToolResults(allocator, &results);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, formatted, .{

test "formatNativeToolResults empty results" {
    const allocator = std.testing.allocator;
    const formatted = try formatNativeToolResults(allocator, &.{

test "formatNativeToolResults escapes special characters in output" {
    const allocator = std.testing.allocator;
    const formatted = try formatNativeToolResults(allocator, &results);

    // Verify it's valid JSON (will fail if escaping is broken)
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, formatted, .{

test "DispatcherKind enum values" {

// ── parseToolCalls with OpenAI JSON format ──────────────────────

test "parseToolCalls routes OpenAI JSON to native parser" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


test "parseToolCalls falls back to XML when JSON has no tool_calls" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


// ── isNativeJsonFormat ──────────────────────────────────────────

test "isNativeJsonFormat true for valid native JSON" {

test "isNativeJsonFormat true with leading whitespace" {

test "containsToolCallMarkup detects xml and bracket variants" {

test "containsToolCallMarkup detects orphan closing tag" {
    // Model sometimes emits </tool_call> without an opener; must be suppressed.

test "isNativeJsonFormat false for XML response" {

test "isNativeJsonFormat false for plain text" {

test "isNativeJsonFormat false for empty string" {

test "isNativeJsonFormat false for array" {

// ── parseStructuredToolCalls ────────────────────────────────────

test "parseStructuredToolCalls converts ToolCall slice" {
    const allocator = std.testing.allocator;

    const result = try parseStructuredToolCalls(allocator, &tool_calls);


test "parseStructuredToolCalls skips empty name" {
    const allocator = std.testing.allocator;

    const result = try parseStructuredToolCalls(allocator, &tool_calls);


test "parseStructuredToolCalls empty input" {
    const allocator = std.testing.allocator;
    const empty: []const providers.ToolCall = &.{

test "parseStructuredToolCalls empty id becomes null" {
    const allocator = std.testing.allocator;

    const result = try parseStructuredToolCalls(allocator, &tool_calls);


// ── extractJsonObject with arrays ───────────────────────────────

test "extractJsonObject finds array" {
    const input = "some text [1, 2, 3] more text";
    const result = extractJsonObject(input).?;

test "extractJsonObject finds nested array" {
    const input = "[[1, 2], [3, 4]]";
    const result = extractJsonObject(input).?;

test "extractJsonObject prefers earlier bracket over brace" {
    const input = "[{

test "extractJsonObject prefers earlier brace over bracket" {
    const input = "{

// ── JSON Repair Tests ───────────────────────────────────────────

test "repairJson removes trailing commas" {
    const allocator = std.testing.allocator;
    const result = try repairJson(allocator, "{

test "repairJson removes trailing comma in array" {
    const allocator = std.testing.allocator;
    const result = try repairJson(allocator, "[1, 2, 3,]");
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{

test "repairJson balances unclosed braces" {
    const allocator = std.testing.allocator;
    const result = try repairJson(allocator, "{

test "repairJson balances unclosed brackets" {
    const allocator = std.testing.allocator;
    const result = try repairJson(allocator, "[1, 2, 3");
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{

test "repairJson balances unclosed quote" {
    const allocator = std.testing.allocator;
    const result = try repairJson(allocator, "{

test "repairJson escapes newlines in strings" {
    const allocator = std.testing.allocator;
    const result = try repairJson(allocator, "{

test "repairJson passes through valid JSON unchanged" {
    const allocator = std.testing.allocator;
    const valid = "{

test "repairJson handles combined issues" {
    const allocator = std.testing.allocator;
    // Trailing comma + unclosed brace
    const result = try repairJson(allocator, "{

test "parseToolCallJson with trailing comma repair" {
    const allocator = std.testing.allocator;
    const result = try parseToolCallJson(allocator, "{

test "parseToolCallJson with unclosed brace repair" {
    const allocator = std.testing.allocator;
    const result = try parseToolCallJson(allocator, "{

test "parseToolCallJson robustness" {
    const allocator = std.testing.allocator;

    // Case 1: JSON-in-JSON (name field is a whole JSON object)
    const json1 = "{

test "parseToolCallJson salvages malformed quoted colon tool name" {
    const allocator = std.testing.allocator;
    const raw = "{

test "parseToolCallJson salvages malformed quoted colon tool name with repaired arguments" {
    const allocator = std.testing.allocator;
    const raw = "{

test "parseToolCalls salvages malformed quoted colon tool name" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


test "parseToolCalls does not salvage unrelated invalid tool name" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


test "parseXmlToolCalls minimax format" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


test "parseXmlToolCalls minimax format robustness" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


test "parseXmlToolCalls hybrid format" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


test "parseXmlToolCalls tool-tag hybrid format" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


test "parseXmlToolCalls square bracket format" {
    const allocator = std.testing.allocator;

    const result = try parseToolCalls(allocator, response);


// ── Hardening tests (issue #16 audit) ───────────────────────────

test "parseFunctionTagCall parameters bounded by </function>" {
    const allocator = std.testing.allocator;
    // Two function blocks concatenated — second block's params must NOT leak into first
    const inner = "<function=shell><parameter=command>echo hi</parameter></function><function=file_read><parameter=path>/etc/passwd</parameter></function>";
    const call = try parseFunctionTagCall(allocator, inner);
    // Only "command" parameter should be present, not "path"

test "parseFunctionTagCall rejects invalid function name with special chars" {
    const allocator = std.testing.allocator;

test "parseFunctionTagCall accepts valid names with dots dashes underscores" {
    const allocator = std.testing.allocator;
    const call = try parseFunctionTagCall(allocator, "<function=my-tool_v2.0><parameter=key>val</parameter></function>");

test "parseXmlToolCalls function-tag fallback when JSON has braces in value" {
    const allocator = std.testing.allocator;
    // The parameter value contains {hello} which extractJsonObject will pick up,
    // but parseToolCallJson will fail — function-tag should still be tried as fallback
    const result = try parseXmlToolCalls(allocator, response);

// ── buildAssistantHistoryWithToolCalls tests ─────────────────────

test "buildAssistantHistoryWithToolCalls with text and calls" {
    const allocator = std.testing.allocator;

    // Should contain the response text
    // Should contain tool_call XML tags
    // Should contain tool names
    // Should contain two tool_call tags
    var count: usize = 0;
    var search = result;

test "buildAssistantHistoryWithToolCalls empty text" {
    const allocator = std.testing.allocator;

    // Should NOT start with a newline (no empty text prefix)

test "buildAssistantHistoryWithToolCalls no calls" {
    const allocator = std.testing.allocator;


test "buildAssistantHistoryWithToolCalls empty text and no calls" {
    const allocator = std.testing.allocator;


test "buildAssistantHistoryWithToolCalls preserves arguments JSON" {
    const allocator = std.testing.allocator;


test "buildAssistantHistoryWithToolCalls escapes special chars in name" {
    const allocator = std.testing.allocator;

    // The name should be properly JSON-escaped, so the output must be valid JSON inside <tool_call>
    // Find the JSON between <tool_call> tags
    const tc_start = std.mem.indexOf(u8, result, "<tool_call>\n").?;
    const json_start = tc_start + "<tool_call>\n".len;
    const tc_end = std.mem.indexOf(u8, result[json_start..], "\n</tool_call>").?;
    const json_str = result[json_start .. json_start + tc_end];

    // Must be valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{
