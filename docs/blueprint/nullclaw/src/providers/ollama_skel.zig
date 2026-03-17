const std = @import("std");
const root = @import("root.zig");

const Provider = root.Provider;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;
const ToolSpec = root.ToolSpec;

// ─── Tool Call Response Structures ───────────────────────────────────────────

const OllamaFunction = struct {

const OllamaToolCall = struct {

const OllamaMessage = struct {

const OllamaChatResponse = struct {

// ─── Tool Call Helpers ───────────────────────────────────────────────────────

/// Extract actual tool name and arguments from potentially quirky tool call formats.
///
/// Handles 3 patterns local models commonly produce:
/// 1. Nested wrapper: {"name":"tool_call","arguments":{"name":"shell","arguments":{...}}}
/// 2. Prefixed names: "tool.shell" -> "shell"
/// 3. Normal: return as-is
    // Pattern 1: Nested tool_call wrapper
                    const nested_args = if (arguments.object.get("arguments")) |a| a else std.json.Value{

    // Pattern 2: Prefixed tool name (tool.shell -> shell, tools.shell -> shell)

    // Pattern 3: Normal

/// Convert Ollama native tool calls to the JSON format expected by the agent loop.
///
/// Produces OpenAI-compatible JSON:
/// {"content":"","tool_calls":[{"id":"call_0","type":"function","function":{"name":"shell","arguments":"{...}"}}]}
    const tool_calls = message.tool_calls orelse return try allocator.dupe(u8, message.content orelse "");

    var result: std.ArrayListUnmanaged(u8) = .empty;



        const extracted = extractToolNameAndArgs(allocator, tc.function.name, tc.function.arguments);

        // Serialize arguments to string

        // Escape the args_str for embedding in JSON string
        const escaped_args = try jsonEscapeString(allocator, args_str);

        // Build the call ID




/// Escape a string for embedding inside a JSON string value.
fn jsonEscapeString(allocator: std.mem.Allocator, input: []const u8) ![]u8

fn extractDataUriPayload(image: []const u8) []const u8

    const escaped = try jsonEscapeString(allocator, value);

/// Ollama local LLM provider.
///
/// Endpoints:
/// - POST {base_url}/api/chat
/// - No authentication required (local service)
pub const OllamaProvider = struct {

/// Build a full chat request JSON body from a ChatRequest (Ollama format).
    var buf: std.ArrayListUnmanaged(u8) = .empty;


        const escaped = try jsonEscapeString(allocator, msg.content);
        // Append images array if content_parts contains base64 images
            var has_images = false;
                        // Ollama API only supports base64-encoded images, not URLs.
                        // Extract payload from data: URIs; skip regular HTTP URLs.
                            const value = extractDataUriPayload(img.url);



    var temp_buf: [16]u8 = undefined;
    const temp_str = std.fmt.bufPrint(&temp_buf, "{


// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "default url" {
    const p = OllamaProvider.init(std.testing.allocator, null);

test "custom url trailing slash" {
    const p = OllamaProvider.init(std.testing.allocator, "http://192.168.1.100:11434/");

test "chat url is correct" {
    const p = OllamaProvider.init(std.testing.allocator, null);
    const url = try p.chatUrl(std.testing.allocator);

test "buildRequestBody with system" {
    const body = try OllamaProvider.buildRequestBody(std.testing.allocator, "You are helpful", "hello", "llama3", 0.7);

test "buildRequestBody without system" {
    const body = try OllamaProvider.buildRequestBody(std.testing.allocator, null, "test", "mistral", 0.0);

test "parseResponse extracts content" {
    const result = try OllamaProvider.parseResponse(std.testing.allocator, body);

test "parseResponse empty content" {
    const result = try OllamaProvider.parseResponse(std.testing.allocator, body);

test "supportsNativeTools returns true" {
    var p = OllamaProvider.init(std.testing.allocator, null);
    const prov = p.provider();

// ─── Tool Call Tests ─────────────────────────────────────────────────────────

test "extractToolNameAndArgs with normal name" {
    const result = extractToolNameAndArgs(std.testing.allocator, "shell", .null);

test "extractToolNameAndArgs with tool. prefix" {
    const result = extractToolNameAndArgs(std.testing.allocator, "tool.shell", .null);

test "extractToolNameAndArgs with tools. prefix" {
    const result = extractToolNameAndArgs(std.testing.allocator, "tools.file_read", .null);

test "ollama buildChatRequestBody with images" {
    const alloc = std.testing.allocator;
    const body = try buildChatRequestBody(alloc, .{

test "ollama buildChatRequestBody without content_parts" {
    const alloc = std.testing.allocator;
    const body = try buildChatRequestBody(alloc, .{

test "ollama buildChatRequestBody with data URI image_url extracts base64 payload" {
    const alloc = std.testing.allocator;
    const body = try buildChatRequestBody(alloc, .{

test "ollama buildChatRequestBody skips HTTP URL image_url" {
    const alloc = std.testing.allocator;
    const body = try buildChatRequestBody(alloc, .{

test "ollama buildChatRequestBody includes native tools" {
    const alloc = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, body, .{

test "extractToolNameAndArgs with nested tool_call wrapper" {
    // Build a JSON object: {"name":"shell","arguments":{"command":"date"}}
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{

test "extractToolNameAndArgs with tool.call wrapper" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{

test "formatToolCallsForLoop with single tool call" {
    const alloc = std.testing.allocator;

    const result = try formatToolCallsForLoop(alloc, parsed.value.message);

    // Verify it's valid JSON
    const verify = try std.json.parseFromSlice(std.json.Value, alloc, result, .{

test "formatToolCallsForLoop with no tool calls returns content" {
    const alloc = std.testing.allocator;
    const result = try formatToolCallsForLoop(alloc, msg);

test "formatToolCallsForLoop with empty tool calls returns content" {
    const alloc = std.testing.allocator;
    const empty_tcs: []const OllamaToolCall = &.{

test "formatToolCallsForLoop generates call_N id when id is null" {
    const alloc = std.testing.allocator;
    const result = try formatToolCallsForLoop(alloc, msg);


test "parseResponse with tool calls produces formatted JSON" {
    const alloc = std.testing.allocator;
    const result = try OllamaProvider.parseResponse(alloc, body);

    // Should be valid JSON with tool_calls
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, result, .{

test "parseResponse thinking-only returns fallback message" {
    const alloc = std.testing.allocator;
    const result = try OllamaProvider.parseResponse(alloc, body);


test "parseResponse with tool_call nested wrapper unwraps correctly" {
    const alloc = std.testing.allocator;
    const result = try OllamaProvider.parseResponse(alloc, body);

    // The formatted output should contain the unwrapped tool name "shell"
    // And should NOT have "tool_call" as the function name

test "jsonEscapeString escapes quotes and backslashes" {
    const alloc = std.testing.allocator;
    const result = try jsonEscapeString(alloc, "he said \"hello\\world\"");
