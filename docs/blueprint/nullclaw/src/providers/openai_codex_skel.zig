//! OpenAI Codex provider — connects to ChatGPT subscription API via OAuth tokens.
//!
//! Uses the Codex Responses API at chatgpt.com/backend-api/codex/responses,
//! authenticated via OAuth device code flow (RFC 8628). Users with ChatGPT
//! Plus/Pro subscriptions can use this without separate API tokens.

const std = @import("std");
const root = @import("root.zig");
const sse = @import("sse.zig");
const auth = @import("../auth.zig");
const codex_support = @import("../codex_support.zig");
const http_util = @import("../http_util.zig");

const Provider = root.Provider;
const ChatMessage = root.ChatMessage;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;
const StreamChatResult = root.StreamChatResult;

// ── Constants ────────────────────────────────────────────────────────────

pub const CODEX_API_URL = "https://chatgpt.com/backend-api/codex/responses";
pub const OAUTH_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
pub const OAUTH_DEVICE_URL = "https://auth.openai.com/oauth/device/code";
pub const OAUTH_TOKEN_URL = "https://auth.openai.com/oauth/token";
pub const OAUTH_SCOPE = "openid profile email offline_access";
pub const CREDENTIAL_KEY = "openai-codex";

// ── Provider ─────────────────────────────────────────────────────────────

pub const OpenAiCodexProvider = struct {

// ── Body Builders ────────────────────────────────────────────────────────

/// Build a Codex request body from system prompt and messages.
/// Maps: system → instructions, user → "user" item with input_text, assistant → "assistant" item.
    var buf: std.ArrayListUnmanaged(u8) = .empty;


    // Extract system/instructions from messages
    var instructions: ?[]const u8 = system;


    // Build input items array — last user message becomes input, rest are context
    var first = true;


    // Fixed fields

    // Reasoning
    const effort = reasoning_effort orelse "medium";


/// Build a simple Codex request body for chatWithSystem shortcut.
    var buf: std.ArrayListUnmanaged(u8) = .empty;





// ── SSE / HTTP ───────────────────────────────────────────────────────────

/// Non-streaming Codex request — spawns curl with SSE, accumulates text deltas, returns final text.
    // Use the streaming path internally and just accumulate
    var accumulated: std.ArrayListUnmanaged(u8) = .empty;

    const NoopCtx = struct {

    var ctx = NoopCtx{

/// Streaming Codex request — spawns curl, parses Codex SSE events, invokes callback per delta.
    // Build argv on stack
    var argv_buf: [32][]const u8 = undefined;
    var argc: usize = 0;


    // Add proxy from environment if set
    const proxy = http_util.getProxyFromEnv(allocator) catch null;




    var child = std.process.Child.init(argv_buf[0..argc], allocator);



    // Read stdout line by line, parse Codex SSE events
    var accumulated: std.ArrayListUnmanaged(u8) = .empty;

    var line_buf: std.ArrayListUnmanaged(u8) = .empty;

    const file = child.stdout.?;
    var read_buf: [4096]u8 = undefined;
    var saw_text_delta = false;
    var emitted_text_fallback = false;
    var emitted_tool_payload = false;

        const n = file.read(&read_buf) catch break;

                        const is_tool_payload = std.mem.indexOf(u8, delta_evt.text, "<tool_call>") != null;
                                // Fallback text only when canonical deltas were absent.
                                    // Message snapshot text, fallback-only.
                                    // Completed may repeat tool payloads already emitted from output_item.done.
                                    // Completed text is fallback-only when no deltas were seen.

    // Send final chunk

    // Drain remaining stdout
        const n = file.read(&read_buf) catch break;

    const term = child.wait() catch return error.CurlWaitError;



// ── SSE Event Parsing ────────────────────────────────────────────────────

/// Result of parsing a single Codex SSE line.
pub const CodexDeltaSource = enum {


    const type_val = part_obj.get("type") orelse return;
    const text_val = part_obj.get("text") orelse return;

fn appendResponseContentText(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, content_val: std.json.Value) !void

fn firstTextFromContent(content_val: std.json.Value) ?[]const u8


    const trimmed_args = std.mem.trim(u8, arguments_json, " \t\r\n");
        // Keep shape valid if backend returns non-JSON arguments.


fn extractOutputItemText(item_obj: std.json.ObjectMap) ?[]const u8

fn extractOutputItemToolCallXml(allocator: std.mem.Allocator, item_obj: std.json.ObjectMap) !?[]u8

fn extractCompletedText(allocator: std.mem.Allocator, root_obj: std.json.ObjectMap) !?[]u8

fn extractCompletedToolCalls(allocator: std.mem.Allocator, root_obj: std.json.ObjectMap) !?[]u8

/// Parse a single Codex SSE event line.
///
/// Codex SSE format: `event: <type>\ndata: {JSON}`
/// Event types:
/// - "response.output_text.delta" → extract "delta" field
/// - "response.output_text.done" → optional final text chunk
/// - "response.output_item.done" / "response.content_part.done" → message/tool-call payload
/// - "response.completed" / "response.done" → done
/// - "error" / "response.failed" → error
pub fn parseCodexSseEvent(allocator: std.mem.Allocator, line: []const u8) !CodexSseResult

// ── Helpers ──────────────────────────────────────────────────────────────

/// Normalize model name — strip "openai-codex/" prefix if present.
pub fn normalizeModel(model: []const u8) []const u8

/// Extract account_id from a JWT access token.
/// Splits on '.', base64url-decodes segment[1], parses JSON.
/// Checks keys: account_id, accountId, acct, sub, https://api.openai.com/account_id.
pub fn extractAccountIdFromJwt(allocator: std.mem.Allocator, token: []const u8) !?[]const u8

// ── Codex CLI Token Import ────────────────────────────────────────────────

/// Try to load OAuth tokens from Codex CLI at ~/.codex/auth.json.
/// Returns an OAuthToken with access_token, refresh_token, and decoded JWT exp.
/// Returns null on any error (file not found, parse failure, etc.).
pub fn tryLoadCodexCliToken(allocator: std.mem.Allocator) ?auth.OAuthToken

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "buildCodexBody with system and user messages" {
    const body = try buildCodexBody(std.testing.allocator, null, &messages, "o4-mini", null);

    // Should contain model
    // Should contain instructions from system message
    // Should contain user message
    // Should contain assistant message
    // Should contain store=false
    // Should contain stream=true
    // Should contain reasoning

test "buildSimpleCodexBody correct JSON" {
    const body = try buildSimpleCodexBody(std.testing.allocator, "Be brief", "What is 2+2?", "o4-mini");


test "buildSimpleCodexBody without system prompt" {
    const body = try buildSimpleCodexBody(std.testing.allocator, null, "Hello", "o4-mini");


test "normalizeModel strips openai-codex/ prefix" {

test "normalizeModel preserves model without prefix" {

test "extractAccountIdFromJwt with valid JWT" {
    // Build a fake JWT: header.payload.signature
    // Payload: {"sub":"user-12345","account_id":"acct-abc"}
    const payload = "{

test "extractAccountIdFromJwt falls back to sub claim" {
    const payload = "{

test "extractAccountIdFromJwt returns null for missing claims" {
    const payload = "{

test "extractAccountIdFromJwt returns null for malformed token" {
    const result1 = try extractAccountIdFromJwt(std.testing.allocator, "not-a-jwt");

    const result2 = try extractAccountIdFromJwt(std.testing.allocator, "a.b");

    const result3 = try extractAccountIdFromJwt(std.testing.allocator, "");

test "parseCodexSseEvent delta event" {
    const line = "data:{

test "parseCodexSseEvent accepts data prefix without space" {
    const line = "data:{

test "parseCodexSseEvent done event" {
    const line = "data:{

test "parseCodexSseEvent output_text.done with text emits delta" {
    const line = "data:{

test "parseCodexSseEvent output_text.done without text does not finish stream" {
    const line = "data:{

test "parseCodexSseEvent content_part.done emits text delta" {
    const result = try parseCodexSseEvent(std.testing.allocator, line);

test "parseCodexSseEvent output_item.done message emits text delta" {
    const result = try parseCodexSseEvent(std.testing.allocator, line);

test "parseCodexSseEvent output_item.done function_call emits xml tool call" {
    const result = try parseCodexSseEvent(std.testing.allocator, line);

test "parseCodexSseEvent response.completed extracts text from response output" {
    const result = try parseCodexSseEvent(std.testing.allocator, line);

test "parseCodexSseEvent response.completed extracts function_call from response output" {
    const result = try parseCodexSseEvent(std.testing.allocator, line);

test "parseCodexSseEvent response.refusal.delta emits delta" {
    const line = "data:{

test "parseCodexSseEvent error event" {
    const line = "data:{

test "parseCodexSseEvent skips event: lines" {
    const result = try parseCodexSseEvent(std.testing.allocator, "event: response.output_text.delta");

test "parseCodexSseEvent skips empty lines" {
    const result = try parseCodexSseEvent(std.testing.allocator, "");

test "parseCodexSseEvent DONE sentinel" {
    const result = try parseCodexSseEvent(std.testing.allocator, "data: [DONE]");

test "parseCodexSseEvent response.done event" {
    const line = "data:{

test "parseCodexSseEvent response.failed event" {
    const line = "data:{

test "buildCodexBody with explicit reasoning effort" {
    const body = try buildCodexBody(std.testing.allocator, null, &messages, "o4-mini", "high");

