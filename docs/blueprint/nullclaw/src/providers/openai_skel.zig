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

/// OpenAI API provider.
///
/// Endpoints:
/// - POST https://api.openai.com/v1/chat/completions
/// - Authorization: Bearer <key>
pub const OpenAiProvider = struct {
    /// Optional User-Agent header for HTTP requests.

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "buildRequestBody without system" {
    const body = try OpenAiProvider.buildRequestBody(std.testing.allocator, null, "hello", "gpt-4o", 0.7);

test "buildRequestBody with system" {
    const body = try OpenAiProvider.buildRequestBody(std.testing.allocator, "You are helpful", "hello", "gpt-4o", 0.7);

test "buildRequestBody reasoning model omits temperature" {
    const body = try OpenAiProvider.buildRequestBody(std.testing.allocator, null, "hello", "gpt-5.2", 0.1);

test "parseTextResponse single choice" {
    const result = try OpenAiProvider.parseTextResponse(std.testing.allocator, body);

test "parseTextResponse empty choices" {

test "parseTextResponse classifies rate-limit errors" {

test "parseNativeResponse with tool calls" {
    const response = try OpenAiProvider.parseNativeResponse(std.testing.allocator, body);

test "supportsNativeTools returns true" {
    var p = OpenAiProvider.init(std.testing.allocator, "key", null);
    const prov = p.provider();

test "parseTextResponse multiple choices returns first" {
    const result = try OpenAiProvider.parseTextResponse(std.testing.allocator, body);

test "parseNativeResponse text only no tool calls" {
    const response = try OpenAiProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse empty choices fails" {

test "parseNativeResponse multiple tool calls" {
    const response = try OpenAiProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse model field extracted" {
    const response = try OpenAiProvider.parseNativeResponse(std.testing.allocator, body);

test "buildRequestBody includes temperature zero" {
    const body = try OpenAiProvider.buildRequestBody(std.testing.allocator, null, "hello", "gpt-4o", 0.0);

test "buildChatRequestBody reasoning model uses max_completion_tokens" {
    const body = try OpenAiProvider.buildChatRequestBody(std.testing.allocator, req, "gpt-5.2", 0.2);

test "buildStreamingChatRequestBody reasoning model uses max_completion_tokens" {
    const body = try OpenAiProvider.buildStreamingChatRequestBody(std.testing.allocator, req, "gpt-5.2", 0.2);

test "provider getName returns OpenAI" {
    var p = OpenAiProvider.init(std.testing.allocator, "key", null);
    const prov = p.provider();

test "validateUserAgent rejects CRLF injection" {

test "isReasoningModel detects all reasoning prefixes" {
    // Non-reasoning models

test "o3-mini omits temperature" {
    const body = try OpenAiProvider.buildRequestBody(std.testing.allocator, null, "hello", "o3-mini", 0.5);

test "buildChatRequestBody without max_tokens omits it" {
    const req = root.ChatRequest{

test "o1 uses max_completion_tokens" {
    const body = try OpenAiProvider.buildChatRequestBody(std.testing.allocator, req, "o1", 0.7);

test "reasoning model with reasoning_effort=none includes temperature" {
    const body = try OpenAiProvider.buildChatRequestBody(std.testing.allocator, req, "gpt-5.1", 0.3);

test "reasoning_effort emitted in request body" {
    const body = try OpenAiProvider.buildChatRequestBody(std.testing.allocator, req, "o3-mini", 0.7);

test "o4-mini omits temperature in streaming request" {
    const body = try OpenAiProvider.buildStreamingChatRequestBody(std.testing.allocator, req, "o4-mini", 0.7);

test "codex-mini uses max_completion_tokens" {
    const body = try OpenAiProvider.buildChatRequestBody(std.testing.allocator, req, "codex-mini-latest", 0.5);

test "reasoning_effort on non-reasoning model is not emitted" {
    const body = try OpenAiProvider.buildChatRequestBody(std.testing.allocator, req, "gpt-4o", 0.7);
    // Non-reasoning model: reasoning_effort should NOT appear
    // Should still have temperature

test "reasoning_effort medium omits temperature" {
    const body = try OpenAiProvider.buildChatRequestBody(std.testing.allocator, req, "o3-mini", 0.5);
