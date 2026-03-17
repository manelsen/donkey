const std = @import("std");
const root = @import("root.zig");
const sse = @import("sse.zig");
const error_classify = @import("error_classify.zig");

const Provider = root.Provider;
const ChatMessage = root.ChatMessage;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;
const ToolCall = root.ToolCall;
const ToolSpec = root.ToolSpec;
const TokenUsage = root.TokenUsage;

/// OpenRouter provider — AI model aggregator.
///
/// Endpoints:
/// - POST https://openrouter.ai/api/v1/chat/completions
/// - Authorization: Bearer <key>
/// - Extra headers: HTTP-Referer, X-Title
pub const OpenRouterProvider = struct {

/// Append OpenRouter's unified reasoning parameter when reasoning_effort is set.
/// OpenRouter models like Kimi K2.5 use {"reasoning":{"effort":"high"}} to include
/// the reasoning trace in the response, regardless of whether they recognize
/// the top-level reasoning_effort field that appendGenerationFields emits for o-series models.
    const effort = root.normalizeOpenAiReasoningEffort(reasoning_effort) orelse return;

/// HTTP GET via curl subprocess with auth header.
fn curlGet(allocator: std.mem.Allocator, url: []const u8, auth_hdr: []const u8) ![]u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "buildRequestBody with system and user" {

test "parseTextResponse single choice" {
    const result = try OpenRouterProvider.parseTextResponse(std.testing.allocator, body);

test "parseTextResponse empty choices" {

test "parseTextResponse classifies context errors" {

test "supportsNativeTools returns true" {
    var p = OpenRouterProvider.init(std.testing.allocator, "key");
    const prov = p.provider();

test "convertMessages produces valid JSON with system, user, assistant" {
    const alloc = std.testing.allocator;
    const result = try OpenRouterProvider.convertMessages(alloc, messages, "Be concise");

    // Verify it's valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, result, .{

test "convertMessages with tool role includes tool_call_id" {
    const alloc = std.testing.allocator;
    const result = try OpenRouterProvider.convertMessages(alloc, messages, null);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, result, .{

test "convertMessages without system prompt" {
    const alloc = std.testing.allocator;
    const result = try OpenRouterProvider.convertMessages(alloc, messages, null);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, result, .{

test "convertMessages escapes special characters" {
    const alloc = std.testing.allocator;
    const result = try OpenRouterProvider.convertMessages(alloc, messages, null);

    // Must parse as valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, result, .{

test "convertTools produces valid JSON schema" {
    const alloc = std.testing.allocator;
    const result = try OpenRouterProvider.convertTools(alloc, tools);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, result, .{

test "convertTools with empty tools returns empty array" {
    const alloc = std.testing.allocator;
    const result = try OpenRouterProvider.convertTools(alloc, &.{

test "warmup does not crash without key" {
    var p = OpenRouterProvider.init(std.testing.allocator, null);

test "buildRequestBody reasoning model omits temperature" {
    const body = try OpenRouterProvider.buildRequestBody(std.testing.allocator, null, "hello", "o3-mini", 0.5);

test "buildChatRequestBody o3 uses max_completion_tokens" {
    const body = try OpenRouterProvider.buildChatRequestBody(std.testing.allocator, req, "o3", 0.7);
    // Reasoning model: no temperature, uses max_completion_tokens

test "buildChatRequestBody escapes OpenRouter reasoning effort value" {
    const body = try OpenRouterProvider.buildChatRequestBody(std.testing.allocator, req, "openrouter/custom", 0.7);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "chatWithHistory fails without key" {
    var p = OpenRouterProvider.init(std.testing.allocator, null);
    const result = p.chatWithHistory(std.testing.allocator, messages, null, "openai/gpt-4o", 0.7);

test "vtable stream_chat is not null" {

test "vtable supports_streaming is not null" {

test "buildStreamingChatRequestBody with stream flag" {
        .{ .role = .user, .content = "test message" },
    const body = try OpenRouterProvider.buildStreamingChatRequestBody(std.testing.allocator, req, "test-model", 0.7);

test "buildStreamingChatRequestBody escapes tool_call_id" {
    const body = try OpenRouterProvider.buildStreamingChatRequestBody(std.testing.allocator, req, "test-model", 0.7);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "streamChatImpl fails without key" {
    var p = OpenRouterProvider.init(std.testing.allocator, null);
    const provider = p.provider();


    var ctx: u8 = 0;

fn testCallback(_: *anyopaque, _: root.StreamChunk) void