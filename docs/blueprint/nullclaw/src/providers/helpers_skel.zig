const std = @import("std");
const json_util = @import("../json_util.zig");
const http_util = @import("../http_util.zig");
const config_types = @import("../config_types.zig");
const root = @import("root.zig");
const ToolSpec = root.ToolSpec;

// ── Think-block parsing ───────────────────────────────────────────────────

const think_open_tag = "<think>";
const think_close_tag = "</think>";

/// Result of splitting a response text at <think>…</think> blocks.
pub const SplitThinkContent = struct {
    /// Text outside think blocks (the user-visible answer).
    /// Concatenated content of all think blocks, or null if none were present.

    var i: usize = 0;
    var depth: usize = 0;

/// Split `text` into visible content and reasoning extracted from <think>…</think> blocks.
/// Both returned slices are caller-owned (allocated with `allocator`).
pub fn splitThinkContent(allocator: std.mem.Allocator, text: []const u8) !SplitThinkContent

/// Strip all <think>…</think> blocks from `text`. Returns caller-owned slice.
pub fn stripThinkBlocks(allocator: std.mem.Allocator, text: []const u8) ![]const u8

/// Extract api_key from a config-like struct (supports both Config.defaultProviderKey() and plain .api_key field).
fn resolveApiKeyFromCfg(cfg: anytype) ?[]const u8

/// High-level complete function that routes to the right provider via HTTP.
/// Used by agent.zig for backward compatibility.
pub fn complete(allocator: std.mem.Allocator, cfg: anytype, prompt: []const u8) ![]const u8

/// Like complete() but prepends a system prompt. OpenAI-compatible format.
pub fn completeWithSystem(allocator: std.mem.Allocator, cfg: anytype, system_prompt: []const u8, prompt: []const u8) ![]const u8

/// Provider URL mapping for the legacy complete() function.
pub fn providerUrl(provider_name: []const u8) []const u8

/// Build a JSON request body for the legacy complete() function.
pub fn buildRequestBody(allocator: std.mem.Allocator, model: []const u8, prompt: []const u8, temperature: f64, max_tokens: u32) ![]const u8

/// Build a JSON request body with a system prompt (OpenAI-compatible format).
pub fn buildRequestBodyWithSystem(allocator: std.mem.Allocator, model: []const u8, system: []const u8, prompt: []const u8, temperature: f64, max_tokens: u32) ![]const u8

/// Check if a model name indicates an OpenAI reasoning model
/// (o1, o3, o4-mini, gpt-5*, codex-mini).
pub fn isReasoningModel(model: []const u8) bool

/// Append model-specific generation controls to a JSON request body buffer:
/// - non-reasoning: `temperature` + optional `max_tokens`
/// - reasoning + reasoning_effort=="none": `temperature` + `max_completion_tokens`
/// - reasoning (otherwise): `max_completion_tokens` only (no temperature)
/// Always emits normalized `reasoning_effort` when set on a reasoning model.
/// OpenAI-compatible reasoning values are normalized as:
/// - `minimal` -> `low`
/// - `xhigh` -> `high`
        // Non-reasoning model: temperature + max_tokens
        var temp_buf: [16]u8 = undefined;
        const temp_str = std.fmt.bufPrint(&temp_buf, "{

    const normalized_effort = normalizeOpenAiReasoningEffort(reasoning_effort);

    // Reasoning model: temperature only if reasoning_effort == "none"
    const effort_is_none = if (normalized_effort) |re| std.mem.eql(u8, re, "none") else false;
        var temp_buf: [16]u8 = undefined;
        const temp_str = std.fmt.bufPrint(&temp_buf, "{

    // Reasoning model: always use max_completion_tokens instead of max_tokens
        var max_buf: [16]u8 = undefined;
        const max_str = std.fmt.bufPrint(&max_buf, "{

    // Emit reasoning_effort when set (JSON-escaped for safety)

pub fn normalizeOpenAiReasoningEffort(reasoning_effort: ?[]const u8) ?[]const u8

const GeminiReasoningEffort = enum {


const GeminiThinkingTarget = enum {

fn parseGeminiReasoningEffort(reasoning_effort: ?[]const u8) ?GeminiReasoningEffort

fn geminiThinkingProfile(model: []const u8, reasoning_effort: ?[]const u8) ?GeminiThinkingProfile

/// Append Gemini/Vertex thinking controls under generationConfig when reasoning effort is set.
/// Mapping:
/// - Gemini 3 models => `thinkingConfig.thinkingLevel`
/// - Gemini 2.5 models => `thinkingConfig.thinkingBudget`

/// Append Vertex thinking controls under generationConfig when reasoning effort is set.
/// Vertex expects enum-style uppercase values for `thinkingLevel`.

fn normalizeVertexThinkingLevel(level: []const u8) []const u8

    const profile = geminiThinkingProfile(model, reasoning_effort) orelse return;

            var budget_buf: [16]u8 = undefined;
            const budget_str = std.fmt.bufPrint(&budget_buf, "{

/// Serialize a single message's content field (plain string or multimodal content parts array).
/// OpenAI format: text → {"type":"text","text":"..."}, image_url → {"type":"image_url","image_url":{"url":"...","detail":"..."}},
/// image_base64 → {"type":"image_url","image_url":{"url":"data:mime;base64,..."}}.
/// Used by OpenAI, OpenRouter, and Compatible providers.
/// Serialize a single content part (text, image_url, or image_base64) to a JSON string.
pub fn serializeContentPart(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, part: root.ContentPart) !void

pub fn serializeMessageContent(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, msg: root.ChatMessage) !void

/// Serialize tool definitions into an OpenAI-format JSON array, appending directly into `buf`.
/// Format: [{"type":"function","function":{"name":"...","description":"...","parameters":{...}}}]
pub fn convertToolsOpenAI(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, tools: []const ToolSpec) !void

/// Serialize tool definitions into an Anthropic-format JSON array, appending directly into `buf`.
/// Format: [{"name":"...","description":"...","input_schema":{...}}]
pub fn convertToolsAnthropic(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, tools: []const ToolSpec) !void

/// HTTP POST with optional LLM timeout (seconds). 0 = no limit.
/// Automatically reads proxy from HTTPS_PROXY, HTTP_PROXY, or ALL_PROXY environment variables.
pub fn curlPostTimed(allocator: std.mem.Allocator, url: []const u8, body: []const u8, headers: []const []const u8, timeout_secs: u64) ![]u8

/// HTTP POST (application/x-www-form-urlencoded) with optional timeout.
/// Automatically reads proxy from HTTPS_PROXY, HTTP_PROXY, or ALL_PROXY environment variables.
pub fn curlPostFormTimed(allocator: std.mem.Allocator, url: []const u8, body: []const u8, timeout_secs: u64) ![]u8

/// Extract text content from a provider JSON response.
pub fn extractContent(allocator: std.mem.Allocator, body: []const u8) ![]const u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "convertToolsOpenAI produces valid JSON" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const json = buf.items;

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{

test "convertToolsOpenAI empty tools" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "convertToolsAnthropic produces valid JSON" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const json = buf.items;

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{

test "convertToolsAnthropic empty tools" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "providerUrl returns correct URLs" {

test "extractContent parses OpenAI format" {
    const allocator = std.testing.allocator;
    const result = try extractContent(allocator, body);

test "extractContent parses Anthropic format" {
    const allocator = std.testing.allocator;
    const result = try extractContent(allocator, body);

test "buildRequestBody escapes double quotes in prompt" {
    const allocator = std.testing.allocator;
    const body = try buildRequestBody(allocator, "gpt-4o", "say \"hello\"", 0.7, 100);
    // Raw quote would break JSON; escaped form must be present
    // Verify it's valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{

test "buildRequestBody escapes newlines in prompt" {
    const allocator = std.testing.allocator;
    const body = try buildRequestBody(allocator, "gpt-4o", "line1\nline2", 0.7, 100);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{

test "buildRequestBody escapes backslash in prompt" {
    const allocator = std.testing.allocator;
    const body = try buildRequestBody(allocator, "gpt-4o", "path\\to\\file", 0.7, 100);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{

test "buildRequestBodyWithSystem escapes special chars in both fields" {
    const allocator = std.testing.allocator;
    const body = try buildRequestBodyWithSystem(allocator, "gpt-4o", "sys \"role\"", "user\nprompt", 0.7, 100);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{

test "serializeMessageContent plain text" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const msg = root.ChatMessage.user("Hello world");

test "serializeMessageContent with content_parts text" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // Should produce an array with a text part
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{

test "serializeMessageContent with image_base64 part" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // Verify it produces valid JSON with data URI

test "serializeMessageContent with image_url part" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{

test "appendGenerationFields normalizes minimal reasoning effort for gpt-5" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{

test "appendGenerationFields normalizes xhigh reasoning effort for gpt-5" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{

test "appendGeminiThinkingConfig uses thinkingLevel for gemini-3 flash" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{

test "appendGeminiThinkingConfig maps unsupported gemini-3 pro medium to low level" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{

test "appendGeminiThinkingConfig uses thinkingBudget for gemini-2.5 flash" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{

test "appendGeminiThinkingConfig omits none budget for gemini-2.5 pro" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{

test "appendVertexThinkingConfig uses uppercase thinkingLevel for gemini-3 flash" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, buf.items, .{
