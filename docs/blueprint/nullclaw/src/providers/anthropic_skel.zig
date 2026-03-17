const std = @import("std");
const root = @import("root.zig");
const sse = @import("sse.zig");
const error_classify = @import("error_classify.zig");
const config_types = @import("../config_types.zig");
const http_util = @import("../http_util.zig");

const Provider = root.Provider;
const ChatMessage = root.ChatMessage;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;
const ContentPart = root.ContentPart;
const ToolCall = root.ToolCall;
const ToolSpec = root.ToolSpec;
const TokenUsage = root.TokenUsage;

/// Anthropic Claude API provider.
///
/// Supports:
/// - x-api-key authentication (standard API keys)
/// - Bearer token authentication (setup/OAuth tokens starting with sk-ant-oat01-)
/// - Custom base URLs for proxies/self-hosted endpoints
pub const AnthropicProvider = struct {

/// Serialize a single message's content field in Anthropic format.
/// Plain text → JSON string, multimodal → content array with type:text / type:image blocks.
fn serializeAnthropicContent(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, msg: ChatMessage) !void

/// Build a full chat request JSON body from a ChatRequest (Anthropic messages format).
/// System messages are extracted and placed in the top-level "system" field.
/// User/assistant/tool messages go in the "messages" array.
    var buf: std.ArrayListUnmanaged(u8) = .empty;

    // Extract system prompt (Anthropic puts it top-level, not in messages array)
    var system_prompt: ?[]const u8 = null;

    const max_tokens = request.max_tokens orelse AnthropicProvider.DEFAULT_MAX_TOKENS;
    var max_buf: [16]u8 = undefined;
    const max_str = std.fmt.bufPrint(&max_buf, "{

/// Build a streaming chat request JSON body (same as buildChatRequestBody but with "stream":true).
    var buf: std.ArrayListUnmanaged(u8) = .empty;

    // Extract system prompt (Anthropic puts it top-level, not in messages array)
    var system_prompt: ?[]const u8 = null;

    const max_tokens = request.max_tokens orelse AnthropicProvider.DEFAULT_MAX_TOKENS;
    var max_buf2: [16]u8 = undefined;
    const max_str = std.fmt.bufPrint(&max_buf2, "{

    const effort = root.normalizeOpenAiReasoningEffort(reasoning_effort) orelse return;

    // Anthropic extended thinking requires a budget. Keep a conservative floor
    // and never exceed output budget.

    var budget_buf: [16]u8 = undefined;
    const budget_str = std.fmt.bufPrint(&budget_buf, "{

/// HTTP POST with OAuth-specific headers (anthropic-beta, user-agent).
fn curlPostOAuth(allocator: std.mem.Allocator, url: []const u8, body: []const u8, auth_hdr: []const u8, version_hdr: []const u8) ![]u8

pub const AuthHeader = struct {

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "creates with empty key" {
    const p = AnthropicProvider.init(std.testing.allocator, "", null);

test "creates with whitespace key" {
    const p = AnthropicProvider.init(std.testing.allocator, "  sk-ant-test123  ", null);

test "creates with custom base url" {
    const p = AnthropicProvider.init(std.testing.allocator, "sk-ant-test", "https://api.example.com");

test "custom base url trims trailing slash" {
    const p = AnthropicProvider.init(std.testing.allocator, null, "https://api.example.com/");

test "default base url when none provided" {
    const p = AnthropicProvider.init(std.testing.allocator, null, null);

test "setup token detection works" {

test "messages url is correct" {
    const p = AnthropicProvider.init(std.testing.allocator, null, null);
    const url = try p.messagesUrl(std.testing.allocator);

test "messages url with custom base" {
    const p = AnthropicProvider.init(std.testing.allocator, null, "https://proxy.example.com");
    const url = try p.messagesUrl(std.testing.allocator);

test "auth header for regular key" {
    const auth = try AnthropicProvider.authHeaderValue(std.testing.allocator, "sk-ant-regular-key");

test "auth header for setup token" {
    const auth = try AnthropicProvider.authHeaderValue(std.testing.allocator, "sk-ant-oat01-mytoken");

test "buildSimpleRequestBody without system prompt" {

test "buildSimpleRequestBody with system prompt" {

test "parseTextResponse extracts text" {
    const result = try AnthropicProvider.parseTextResponse(std.testing.allocator, body);

test "parseTextResponse empty content fails" {

test "parseTextResponse classifies rate-limit errors" {

test "parseNativeResponse with text and tool_use" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "supportsNativeTools returns true" {
    var p = AnthropicProvider.init(std.testing.allocator, "key", null);
    const prov = p.provider();

test "parseTextResponse multiple blocks returns first text" {
    const result = try AnthropicProvider.parseTextResponse(std.testing.allocator, body);

test "parseNativeResponse text only no tool calls" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse tool_use only no text" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse empty content array" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse skips tool_use with empty name" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse multiple tool calls" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse model field extracted" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse trims whitespace text" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse skips whitespace-only text blocks" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "provider getName returns Anthropic" {
    var p = AnthropicProvider.init(std.testing.allocator, "key", null);
    const prov = p.provider();

test "parseNativeResponse thinking block populates reasoning_content" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse thinking block only no visible text" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse usage missing defaults to zero" {
    const response = try AnthropicProvider.parseNativeResponse(std.testing.allocator, body);

// ── Streaming Tests ─────────────────────────────────────────────

test "buildStreamingChatRequestBody contains stream true" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody defaults max_tokens to runtime fallback" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody emits thinking config when reasoning_effort is set" {
    const allocator = std.testing.allocator;

    const body = try buildChatRequestBody(allocator, req, "claude-3-opus", 0.7);


test "buildChatRequestBody omits thinking config when reasoning_effort is none" {
    const allocator = std.testing.allocator;

    const body = try buildChatRequestBody(allocator, req, "claude-3-opus", 0.7);


test "buildStreamingChatRequestBody contains same messages as non-streaming" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "supportsStreamingImpl returns true" {
    var p = AnthropicProvider.init(std.testing.allocator, "key", null);
    const prov = p.provider();

test "vtable stream_chat is not null" {

test "vtable supports_streaming is not null" {

// ── Multimodal Serialization Tests ──────────────────────────────

test "buildChatRequestBody without content_parts serializes plain string" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody with base64 image serializes Anthropic format" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "buildChatRequestBody with image URL serializes Anthropic URL source" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "buildStreamingChatRequestBody with content_parts serializes correctly" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{
