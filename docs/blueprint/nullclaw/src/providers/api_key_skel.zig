const std = @import("std");
const builtin = @import("builtin");
const auth = @import("../auth.zig");
const config_mod = @import("../config_types.zig");
const json_util = @import("../json_util.zig");
const platform = @import("../platform.zig");
const provider_names = @import("../provider_names.zig");

pub const QwenCliCredentials = struct {

const QWEN_OAUTH_TOKEN_ENDPOINT = "https://chat.qwen.ai/api/v1/oauth2/token";
const QWEN_OAUTH_CLIENT_ID = "f0304373b74a44d2b584a3fb70ca9e56";

/// Resolve API key for a provider from config and environment variables.
///
/// Resolution order:
/// 1. Explicitly provided `api_key` parameter (trimmed, filtered if empty)
/// 2. For `qwen-portal` only: `QWEN_OAUTH_TOKEN`, then `~/.qwen/oauth_creds.json`
/// 3. Provider-specific environment variable
/// 4. Generic fallback variables (`NULLCLAW_API_KEY`, `API_KEY`)
    // 1. Explicit key
        const trimmed = std.mem.trim(u8, key, " \t\r\n");

    // 2. Qwen OAuth env/file resolution for the qwen-portal provider only.
            const access_token = try allocator.dupe(u8, creds.access_token);

    // 3. Provider-specific env vars
    const env_candidates = providerEnvCandidates(provider_name);

    // 4. Generic fallbacks
    const fallbacks = [_][]const u8{

fn loadNonEmptyEnv(allocator: std.mem.Allocator, name: []const u8) !?[]u8

fn dupeTrimmedString(allocator: std.mem.Allocator, value: []const u8) !?[]const u8

fn parseEpochMilliseconds(value: std.json.Value) ?i64

pub fn parseQwenCredentialsJson(allocator: std.mem.Allocator, json_bytes: []const u8) ?QwenCliCredentials

    var buf: std.ArrayListUnmanaged(u8) = .empty;








    const file = std.fs.createFileAbsolute(path, .{

    const refresh_token = creds.refresh_token orelse return null;






pub fn tryLoadQwenCliToken(allocator: std.mem.Allocator) ?QwenCliCredentials

fn providerEnvCandidates(name: []const u8) [3][]const u8

/// Resolve API key with config providers as first priority, then env vars:
///   1. providers[].api_key from config
///   2. Provider-specific env var (GROQ_API_KEY, etc.)
///   3. Generic fallbacks (NULLCLAW_API_KEY, API_KEY)

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "NVIDIA_API_KEY env resolves nvidia credential" {
    const allocator = std.testing.allocator;
    // providerEnvCandidates returns NVIDIA_API_KEY for nvidia
    const candidates = providerEnvCandidates("nvidia");
    // Also check aliases
    const candidates_nim = providerEnvCandidates("nvidia-nim");
    const candidates_build = providerEnvCandidates("build.nvidia.com");

test "astrai env candidate is ASTRAI_API_KEY" {
    const candidates = providerEnvCandidates("astrai");

test "vertex env candidate is VERTEX_API_KEY" {
    const candidates = providerEnvCandidates("vertex");

test "qwen uses dashscope api key env candidate" {
    const candidates = providerEnvCandidates("qwen");

test "qwen-portal env candidate uses oauth token" {
    const candidates = providerEnvCandidates("qwen-portal");

test "azure aliases share Azure env candidate" {

test "providerEnvCandidates includes onboarding env hints" {
    const onboard = @import("../onboard.zig");

        const candidates = providerEnvCandidates(provider.key);

        var matched = false;


test "resolveApiKeyFromConfig finds key from providers" {
    const result = try resolveApiKeyFromConfig(std.testing.allocator, "groq", &entries);

test "resolveApiKeyFromConfig matches provider aliases" {
    const result = try resolveApiKeyFromConfig(std.testing.allocator, "azure-openai", &entries);

test "resolveApiKeyFromConfig falls through to env for missing provider" {
    // Falls through to env-based resolution (may or may not find a key)
    const result = try resolveApiKeyFromConfig(std.testing.allocator, "nonexistent", &entries);

test "parseQwenCredentialsJson parses access token" {
    const creds = parseQwenCredentialsJson(std.testing.allocator, "{

test "parseQwenCredentialsJson parses refresh metadata" {


test "parseQwenCredentialsJson normalizes seconds expiry timestamps" {

test "parseQwenCredentialsJson rejects missing access token" {

test "parseQwenCredentialsJson rejects empty access token" {

test "parseQwenCredentialsJson rejects invalid json" {

test "parseQwenCredentialsJson cleans up on invalid token type" {

test "tryLoadQwenCliToken disabled during tests" {

test "QwenCliCredentials isExpired uses expiry_date with refresh buffer" {
    const now_ms = std.time.milliTimestamp();


test "writeQwenCredentialsJson preserves qwen oauth fields" {
    var temp_dir = std.testing.tmpDir(.{

test "resolveApiKey qwen-portal prefers oauth env over dashscope key" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    const oauth_key_z = try std.testing.allocator.dupeZ(u8, "QWEN_OAUTH_TOKEN");
    const oauth_value_z = try std.testing.allocator.dupeZ(u8, "oauth-token");

    const api_key_z = try std.testing.allocator.dupeZ(u8, "DASHSCOPE_API_KEY");
    const api_value_z = try std.testing.allocator.dupeZ(u8, "dashscope-key");

    const result = try resolveApiKey(std.testing.allocator, "qwen-portal", null);
