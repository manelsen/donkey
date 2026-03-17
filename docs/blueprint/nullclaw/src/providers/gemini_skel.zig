const std = @import("std");
const fs_compat = @import("../fs_compat.zig");
const platform = @import("../platform.zig");
const root = @import("root.zig");
const error_classify = @import("error_classify.zig");
const config_types = @import("../config_types.zig");
const http_util = @import("../http_util.zig");
const sse = @import("sse.zig");

const Provider = root.Provider;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;
const OAUTH_REFRESH_TIMEOUT_SECS: u64 = 20;

fn parseExpiresIn(v: std.json.Value) ?i64

fn parseTokenCount(v: std.json.Value) ?u32

fn normalizeTokenUsage(usage: *root.TokenUsage) void

fn parseUsageMetadataValue(v: std.json.Value) ?root.TokenUsage

pub fn extractGeminiUsageMetadata(allocator: std.mem.Allocator, json_str: []const u8) !?root.TokenUsage

fn extractGeminiUsageFromSseLine(allocator: std.mem.Allocator, line: []const u8) !?root.TokenUsage

fn isFormUrlencodedUnreserved(c: u8) bool

    const HEX = "0123456789ABCDEF";


    var body: std.ArrayListUnmanaged(u8) = .empty;



/// Credentials loaded from the Gemini CLI OAuth token file (~/.gemini/oauth_creds.json).
pub const GeminiCliCredentials = struct {
    /// Returns true if the token is expired (or within 5 minutes of expiring).
    /// If expires_at is null, the token is treated as never-expiring.

/// Parse Gemini CLI credentials from a JSON byte slice.
/// Returns null if the JSON is invalid or missing the required `access_token` field.
pub fn parseCredentialsJson(allocator: std.mem.Allocator, json_bytes: []const u8) ?GeminiCliCredentials

/// OAuth token refresh response from Google.
const RefreshResponse = struct {

/// Parse OAuth token refresh response from Google's JSON.
/// Returns null if JSON is invalid or missing required fields.
/// Returned access_token is duped and owned by caller.
pub fn parseRefreshResponse(allocator: std.mem.Allocator, json_bytes: []const u8) ?RefreshResponse

/// Refresh an OAuth token using Google's OAuth2 endpoint.
/// Returns the refresh response (access token owned by caller) or error.
/// Uses builtin.is_test guard to skip actual HTTP calls in tests.
pub fn refreshOAuthToken(allocator: std.mem.Allocator, refresh_token: []const u8) !RefreshResponse

/// Write credentials back to ~/.gemini/oauth_creds.json.
pub fn writeCredentialsJson(allocator: std.mem.Allocator, creds: GeminiCliCredentials, path: []const u8) !void

/// Try to load Gemini CLI OAuth credentials from ~/.gemini/oauth_creds.json.
/// If token is expired but refresh_token is available, attempts to refresh.
/// Returns null on any error (file not found, parse failure, refresh failed, etc.).
pub fn tryLoadGeminiCliToken(allocator: std.mem.Allocator) ?GeminiCliCredentials

/// Authentication method for Gemini.
    /// Explicit API key from config: sent as `?key=` query parameter.
    /// API key from `GEMINI_API_KEY` env var.
    /// API key from `GOOGLE_API_KEY` env var.
    /// OAuth access token from `GEMINI_OAUTH_TOKEN` env var.
    /// OAuth access token from Gemini CLI: sent as `Authorization: Bearer`.

    pub fn isApiKey(self: GeminiAuth) bool

    pub fn credential(self: GeminiAuth) []const u8

    pub fn source(self: GeminiAuth) []const u8

/// Google Gemini provider with support for:
/// - Direct API key (`GEMINI_API_KEY` env var or config)
/// - Gemini CLI OAuth tokens (reuse existing ~/.gemini/ authentication)
/// - Google Cloud ADC (`GOOGLE_APPLICATION_CREDENTIALS`)
pub const GeminiProvider = struct {

/// Build a full chat request JSON body from a ChatRequest (Gemini format).
/// Gemini uses "contents" array with roles "user"/"model", system goes in "system_instruction".
    var buf: std.ArrayListUnmanaged(u8) = .empty;

    // Extract system prompt
    var system_prompt: ?[]const u8 = null;

    var count: usize = 0;
        // Gemini uses "user" and "model" (not "assistant")
                        // Gemini doesn't support direct URLs; include as escaped text reference
                        var text_buf: std.ArrayListUnmanaged(u8) = .empty;


    var temp_buf: [16]u8 = undefined;
    const temp_str = std.fmt.bufPrint(&temp_buf, "{


// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "provider creates without key" {
    const p = GeminiProvider.init(std.testing.allocator, null);

test "provider creates with key" {
    const p = GeminiProvider.init(std.testing.allocator, "test-api-key");

test "provider rejects empty key" {
    const p = GeminiProvider.init(std.testing.allocator, "");
    // Empty key must not be accepted as an explicit key — auth source must
    // NOT be "config". It may fall back to env vars, OAuth, or remain unset
    // depending on the host environment.
    const src = p.authSource();

test "api key url includes key query param" {
    const auth = GeminiAuth{

test "oauth url omits key query param" {
    const auth = GeminiAuth{

test "model name formatting" {
    const auth = GeminiAuth{

test "buildRequestBody with system" {
    const body = try GeminiProvider.buildRequestBody(std.testing.allocator, "Be helpful", "Hello", 0.7);

test "buildRequestBody without system" {
    const body = try GeminiProvider.buildRequestBody(std.testing.allocator, null, "Hello", 0.7);

test "parseResponse extracts text" {
    const result = try GeminiProvider.parseResponse(std.testing.allocator, body);

test "parseChatResponse extracts usageMetadata token counts" {
    const response = try GeminiProvider.parseChatResponse(std.testing.allocator, body);

test "extractGeminiUsageMetadata derives missing total from prompt and completion" {
    const usage = (try extractGeminiUsageMetadata(std.testing.allocator, json)).?;

test "parseResponse error response" {
    const detail = (try root.snapshotLastApiErrorDetail(std.testing.allocator)).?;

test "parseResponse classifies rate-limit errors" {

test "GeminiAuth isApiKey" {
    const key = GeminiAuth{

test "GeminiAuth credential returns raw value" {
    const key = GeminiAuth{

test "GeminiAuth source labels" {

test "parseResponse empty candidates fails" {

test "parseResponse no text field fails" {

test "parseResponse multiple parts concatenates visible text" {
    const result = try GeminiProvider.parseResponse(std.testing.allocator, body);

test "parseChatResponse separates thought parts into reasoning_content" {
    const alloc = std.testing.allocator;
    const response = try GeminiProvider.parseChatResponse(alloc, body);

test "parseChatResponse thought only leaves content null" {
    const alloc = std.testing.allocator;
    const response = try GeminiProvider.parseChatResponse(alloc, body);

test "provider rejects whitespace key" {
    const p = GeminiProvider.init(std.testing.allocator, "   ");
    // Whitespace-only key must not be accepted as an explicit key — auth
    // source must NOT be "config". It may fall back to env vars, OAuth,
    // or remain unset depending on the host environment.
    const src = p.authSource();

test "provider getName returns Gemini" {
    var p = GeminiProvider.init(std.testing.allocator, "key");
    const prov = p.provider();

test "buildUrl with models prefix does not double prefix" {
    const auth = GeminiAuth{

// ════════════════════════════════════════════════════════════════════════════
// Streaming Tests
// ════════════════════════════════════════════════════════════════════════════

test "vtable stream_chat is not null" {

test "vtable supports_streaming is not null" {

test "buildStreamUrl with api key" {
    const auth = GeminiAuth{

test "buildStreamUrl with oauth" {
    const auth = GeminiAuth{

test "parseGeminiSseLine valid delta" {
    const allocator = std.testing.allocator;
    const result = try GeminiProvider.parseGeminiSseLine(allocator, "data:{

test "extractGeminiUsageFromSseLine parses usageMetadata" {
    const line = "data:{

test "parseGeminiSseLine empty line" {
    const result = try GeminiProvider.parseGeminiSseLine(std.testing.allocator, "");

test "parseGeminiSseLine invalid json returns error" {

test "streamChatImpl fails without credentials" {
    // Construct directly with auth=null to avoid picking up env vars or CLI tokens
    var p = GeminiProvider{

// ════════════════════════════════════════════════════════════════════════════
// Gemini CLI OAuth Token Discovery Tests
// ════════════════════════════════════════════════════════════════════════════

test "GeminiCliCredentials isExpired with future timestamp returns false" {
    const future: i64 = std.time.timestamp() + 3600; // 1 hour from now

test "GeminiCliCredentials isExpired with past timestamp returns true" {
    const past: i64 = std.time.timestamp() - 3600; // 1 hour ago

test "GeminiCliCredentials isExpired with null expires_at returns false" {

test "GeminiCliCredentials isExpired with 5-min buffer edge case" {
    // Token expires in exactly 4 minutes — within the 5-minute buffer, so should be expired
    const almost_expired: i64 = std.time.timestamp() + 4 * 60;

    // Token expires in exactly 6 minutes — outside the 5-minute buffer, so should NOT be expired
    const still_valid: i64 = std.time.timestamp() + 6 * 60;

test "tryLoadGeminiCliToken is side-effect free in test mode" {
    // In test mode we always return null to avoid touching real ~/.gemini
    // credentials on developer machines.
    const result = tryLoadGeminiCliToken(std.testing.allocator);

test "parseCredentialsJson valid JSON with all fields" {


test "parseCredentialsJson valid JSON with only access_token" {


test "parseCredentialsJson missing access_token returns null" {
    const result = parseCredentialsJson(std.testing.allocator, json);

test "parseCredentialsJson empty object returns null" {
    const result = parseCredentialsJson(std.testing.allocator, json);

test "parseCredentialsJson empty access_token returns null" {
    const result = parseCredentialsJson(std.testing.allocator, json);

test "parseCredentialsJson invalid JSON returns null" {
    const result = parseCredentialsJson(std.testing.allocator, "not json at all");

test "gemini buildChatRequestBody plain text" {
    const alloc = std.testing.allocator;
    const body = try buildChatRequestBody(alloc, .{

test "gemini buildChatRequestBody honors request max_tokens override" {
    const alloc = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, body, .{

test "gemini buildChatRequestBody maps reasoning_effort to thinkingLevel on gemini-3 flash" {
    const alloc = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, body, .{

test "gemini buildChatRequestBody maps reasoning_effort to thinkingBudget on gemini-2.5" {
    const alloc = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, body, .{

test "gemini buildChatRequestBody with content_parts inlineData" {
    const alloc = std.testing.allocator;
    const body = try buildChatRequestBody(alloc, .{

test "gemini buildChatRequestBody with image_url special chars" {
    const alloc = std.testing.allocator;
    const body = try buildChatRequestBody(alloc, .{

// ════════════════════════════════════════════════════════════════════════════
// OAuth Refresh Tests
// ════════════════════════════════════════════════════════════════════════════

test "parseRefreshResponse extracts access token" {
    const alloc = std.testing.allocator;
    const result = parseRefreshResponse(alloc, json) orelse return error.TestUnexpectedResult;

test "parseRefreshResponse handles error response" {
    const result = parseRefreshResponse(std.testing.allocator, json);

test "parseRefreshResponse handles empty access token" {
    const result = parseRefreshResponse(std.testing.allocator, json);

test "parseRefreshResponse handles missing fields" {
    const result = parseRefreshResponse(std.testing.allocator, json);

test "parseRefreshResponse rejects invalid expires_in float" {
    const result = parseRefreshResponse(std.testing.allocator, json);

test "parseRefreshResponse rejects non-positive expires_in" {

test "refreshOAuthToken returns test token in test mode" {
    const alloc = std.testing.allocator;
    const resp = try refreshOAuthToken(alloc, "test-refresh-token");

test "buildRefreshFormBody percent-encodes reserved chars" {
    const alloc = std.testing.allocator;


test "GeminiAuth env_oauth_token is not api key" {
    const auth = GeminiAuth{

test "provider deinit frees env_oauth_token" {
    const alloc = std.testing.allocator;
    const prov = p.provider();

test "provider deinit frees oauth_token" {
    const alloc = std.testing.allocator;
    const prov = p.provider();

test "writeCredentialsJson produces valid JSON" {
    const alloc = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{

test "writeCredentialsJson without refresh token" {
    const alloc = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{

test "writeCredentialsJson escapes token strings" {
    const alloc = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{
