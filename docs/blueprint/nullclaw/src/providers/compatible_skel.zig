const std = @import("std");
const root = @import("root.zig");
const sse = @import("sse.zig");
const error_classify = @import("error_classify.zig");

const Provider = root.Provider;
const ChatMessage = root.ChatMessage;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;
const ContentPart = root.ContentPart;
const ToolCall = root.ToolCall;
const TokenUsage = root.TokenUsage;

const log = std.log.scoped(.compatible);
const MAX_STREAMING_PROMPT_BYTES: usize = 32 * 1024;

    const sanitized = root.sanitizeApiError(allocator, resp_body) catch null;

    const preview = sanitized orelse "<api error body unavailable>";

fn parseStatusCodeValue(value: std.json.Value) ?u16

fn sliceEqlAsciiFold(a: []const u8, b: []const u8) bool

fn containsAsciiFold(haystack: []const u8, needle: []const u8) bool

fn lookupFallbackStatusCode(root_obj: std.json.ObjectMap) ?u16

fn lookupFallbackMessage(root_obj: std.json.ObjectMap) ?[]const u8

fn isResponsesFallbackMessage(message: []const u8) bool

fn shouldFallbackToResponses(allocator: std.mem.Allocator, body: []const u8) bool

/// How the provider expects the API key to be sent.
pub const AuthStyle = enum {
    /// `Authorization: Bearer <key>`
    /// `x-api-key: <key>`
    /// Custom header name (set via `custom_header` field on the provider)

/// A provider that speaks the OpenAI-compatible chat completions API.
///
/// Used by: Venice, Vercel, Cloudflare, Moonshot, Synthetic, OpenCode,
/// Z.AI, GLM, MiniMax, Bedrock, Qianfan, Groq, Mistral, xAI, DeepSeek,
/// Together, Fireworks, Perplexity, Cohere, Copilot, and custom endpoints.
pub const OpenAiCompatibleProvider = struct {
    /// Optional owned copy of base_url when the caller had to normalize/build it.
    /// Custom header name when auth_style is .custom (e.g. "X-Custom-Key").
    /// When false, do not fall back to /v1/responses on chat completions 404.
    /// GLM/Zhipu does not support the responses API.
    /// When true, collect system message content and prepend it to the first
    /// user message as "[System: …]\n\n…", then skip system-role messages.
    /// Required by providers like MiniMax that reject the system role.
    /// Whether this provider supports native OpenAI-style tool_calls.
    /// When false, the agent uses XML tool format via system prompt.
    /// When set, cap max_tokens in non-streaming requests to this value.
    /// Some providers (e.g. Fireworks) reject large max_tokens without streaming.
    /// When true, include `"thinking":{"type":"enabled"}` in request bodies
    /// when reasoning_effort is set. Required by Z.AI/GLM thinking models.
    /// When true, include `"enable_thinking":true` in request bodies
    /// when reasoning_effort is set. Required by Qwen (DashScope compatible mode).
    /// When true, include `"reasoning_split":true` in request bodies
    /// when reasoning_effort is set. Used by MiniMax to separate reasoning output.
    /// Optional User-Agent header for HTTP requests.
    /// When set, requests will include "User-Agent: {value}" header.

/// Serialize a single message's content field — delegates to shared helper in providers/helpers.zig.
const serializeMessageContent = root.serializeMessageContent;

/// Serialize messages into a JSON array, optionally merging system messages
/// into the first user message (for providers that reject the system role).
        // Standard path: serialize all messages as-is.

    // Merge path: collect system content, prepend to first user message.
    var sys_buf: std.ArrayListUnmanaged(u8) = .empty;

    var first_msg = true;
    var first_user_done = false;



                // Prepend system text as a text part, then serialize original parts
                const sys_prefix = try std.fmt.allocPrint(allocator, "[System:{
                const merged = try std.fmt.allocPrint(allocator, "[System:{


/// Build a full chat request JSON body from a ChatRequest (OpenAI-compatible format).
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const reasoning_enabled = hasCompatReasoningEnabled(request.reasoning_effort);






/// Build a streaming chat request JSON body (identical to buildChatRequestBody but with "stream":true).
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const reasoning_enabled = hasCompatReasoningEnabled(request.reasoning_effort);






fn hasCompatReasoningEnabled(reasoning_effort: ?[]const u8) bool

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "strips trailing slash" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://example.com/", null, .bearer, null);

test "chatCompletionsUrl standard" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://api.openai.com/v1", null, .bearer, null);
    const url = try p.chatCompletionsUrl(std.testing.allocator);

test "chatCompletionsUrl custom full endpoint" {
    const url = try p.chatCompletionsUrl(std.testing.allocator);

test "buildRequestBody with system" {

test "parseTextResponse extracts content" {
    const result = try OpenAiCompatibleProvider.parseTextResponse(std.testing.allocator, body);

test "parseTextResponse strips think blocks" {
    const result = try OpenAiCompatibleProvider.parseTextResponse(std.testing.allocator, body);

test "parseNativeResponse splits think blocks into content and reasoning_content" {
    const result = try OpenAiCompatibleProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse reads native reasoning_content field (Z.AI/GLM style)" {
    const result = try OpenAiCompatibleProvider.parseNativeResponse(std.testing.allocator, body);

test "parseNativeResponse reads native reasoning field (Groq/Cerebras parsed format)" {
    const result = try OpenAiCompatibleProvider.parseNativeResponse(std.testing.allocator, body);

test "buildChatRequestBody emits thinking param for GLM when reasoning_effort set" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody omits thinking param when thinking_param false" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody emits enable_thinking when configured" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody emits reasoning_split when configured" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody omits provider thinking params when reasoning_effort none" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "streamThinkSanitizeCallback strips think blocks across chunk boundaries" {
    const Collector = struct {

    var collector = Collector{

test "streamThinkSanitizeCallback preserves incomplete think tag literals" {
    const Collector = struct {

    var collector = Collector{

test "parseTextResponse empty choices" {

test "parseTextResponse classifies rate-limit errors" {

test "authHeaderValue bearer style" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://example.com", "my-key", .bearer, null);
    const auth = (try p.authHeaderValue(std.testing.allocator)).?;

test "authHeaderValue x-api-key style" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://example.com", "my-key", .x_api_key, null);
    const auth = (try p.authHeaderValue(std.testing.allocator)).?;

test "authHeaderValue no key" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://example.com", null, .bearer, null);

test "chatCompletionsUrl trailing slash stripped" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://api.example.com/v1/", null, .bearer, null);
    const url = try p.chatCompletionsUrl(std.testing.allocator);

test "chatCompletionsUrl without v1" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://api.example.com", null, .bearer, null);
    const url = try p.chatCompletionsUrl(std.testing.allocator);

test "chatCompletionsUrl with v1" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://api.example.com/v1", null, .bearer, null);
    const url = try p.chatCompletionsUrl(std.testing.allocator);

test "buildRequestBody without system" {

test "normalizeProviderModel maps DeepSeek v3.2 aliases to deepseek-chat" {
    const deepseek = OpenAiCompatibleProvider.init(std.testing.allocator, "deepseek", "https://api.deepseek.com", null, .bearer, null);

test "normalizeProviderModel leaves other providers unchanged" {
    const openrouter = OpenAiCompatibleProvider.init(std.testing.allocator, "openrouter", "https://openrouter.ai/api/v1", null, .bearer, null);

test "parseTextResponse with null content fails" {

test "AuthStyle headerName" {

test "provider getName returns custom name" {
    var p = OpenAiCompatibleProvider.init(std.testing.allocator, "Venice", "https://api.venice.ai", "key", .bearer, null);
    const prov = p.provider();

test "chatCompletionsUrl requires exact suffix match" {
    const url = try p.chatCompletionsUrl(std.testing.allocator);

test "supportsNativeTools returns true for compatible" {
    var p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://example.com", "key", .bearer, null);
    const prov = p.provider();

test "capNonStreamingMaxTokens caps request max_tokens above provider limit" {
    const msgs = [_]root.ChatMessage{

test "capNonStreamingMaxTokens keeps request max_tokens when already below limit" {
    const msgs = [_]root.ChatMessage{

test "capNonStreamingMaxTokens leaves request unchanged when limit is unset" {
    const msgs = [_]root.ChatMessage{

// ════════════════════════════════════════════════════════════════════════════
// Responses API tests
// ════════════════════════════════════════════════════════════════════════════

test "responsesUrl standard base" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://api.example.com", null, .bearer, null);
    const url = try p.responsesUrl(std.testing.allocator);

test "responsesUrl with v1 no duplicate" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://api.example.com/v1", null, .bearer, null);
    const url = try p.responsesUrl(std.testing.allocator);

test "responsesUrl derives from chat endpoint" {
    const url = try p.responsesUrl(std.testing.allocator);

test "responsesUrl custom full endpoint preserved" {
    const url = try p.responsesUrl(std.testing.allocator);

test "responsesUrl non-v1 api path uses raw suffix" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://api.example.com/api/coding/v3", null, .bearer, null);
    const url = try p.responsesUrl(std.testing.allocator);

test "shouldFallbackToResponses only for explicit 404 payloads" {

test "responsesUrl requires exact suffix match" {
    const url = try p.responsesUrl(std.testing.allocator);

test "extractResponsesText top-level output_text" {
    const result = try OpenAiCompatibleProvider.extractResponsesText(std.testing.allocator, body);

test "extractResponsesText strips think blocks" {
    const result = try OpenAiCompatibleProvider.extractResponsesText(std.testing.allocator, body);

test "extractResponsesText nested output_text type" {
    const result = try OpenAiCompatibleProvider.extractResponsesText(std.testing.allocator, body);

test "extractResponsesText fallback any text" {
    const result = try OpenAiCompatibleProvider.extractResponsesText(std.testing.allocator, body);

test "extractResponsesText empty returns error" {

test "buildResponsesRequestBody with system" {

test "buildResponsesRequestBody without system" {

test "AuthStyle custom headerName fallback" {

test "authHeaderValue custom style" {
    var p = OpenAiCompatibleProvider.init(std.testing.allocator, "custom", "https://api.example.com", "my-key", .custom, null);
    const auth = (try p.authHeaderValue(std.testing.allocator)).?;

test "authHeaderValue custom style without custom_header falls back" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "custom", "https://api.example.com", "my-key", .custom, null);
    const auth = (try p.authHeaderValue(std.testing.allocator)).?;

// ════════════════════════════════════════════════════════════════════════════
// Streaming tests
// ════════════════════════════════════════════════════════════════════════════

test "buildStreamingChatRequestBody contains stream true" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildStreamingChatRequestBody omits provider thinking params when reasoning_effort none" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "supportsStreaming returns true for compatible" {
    var p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://example.com", "key", .bearer, null);
    const prov = p.provider();

test "validateUserAgent rejects CRLF injection" {

test "vtable has stream_chat not null" {
    var p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://example.com", "key", .bearer, null);
    const prov = p.provider();

test "streaming body has same messages as non-streaming" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "streaming body has model field" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

// ════════════════════════════════════════════════════════════════════════════
// Multimodal serialization tests
// ════════════════════════════════════════════════════════════════════════════

test "buildChatRequestBody without content_parts serializes plain string" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody with image_url content_parts serializes OpenAI array" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "buildChatRequestBody with base64 image serializes as data URI" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "buildChatRequestBody with high detail image_url" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "buildRequestBody reasoning model omits temperature" {
    const body = try OpenAiCompatibleProvider.buildRequestBody(std.testing.allocator, null, "hello", "gpt-5", 0.5);

test "buildChatRequestBody o1 omits temperature" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildStreamingChatRequestBody reasoning model omits temperature" {
    const allocator = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

// ════════════════════════════════════════════════════════════════════════════
// merge_system_into_user tests
// ════════════════════════════════════════════════════════════════════════════

test "merge_system_into_user merges system into first user message" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "merge_system_into_user with no system messages passes through" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "merge_system_into_user false keeps system messages" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "merge_system_into_user field defaults to false" {
    const p = OpenAiCompatibleProvider.init(std.testing.allocator, "test", "https://example.com", null, .bearer, null);

test "merge_system_into_user with multiple system messages concatenates" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "merge_system_into_user preserves assistant messages" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{

test "merge_system_into_user streaming body also merges" {
    const allocator = std.testing.allocator;
    const req = root.ChatRequest{
