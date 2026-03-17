const std = @import("std");
const builtin = @import("builtin");
const platform = @import("../platform.zig");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const isResolvedPathAllowed = @import("path_security.zig").isResolvedPathAllowed;
const SecurityPolicy = @import("../security/policy.zig").SecurityPolicy;
const json_miniparse = @import("../json_miniparse.zig");
const command_summary = @import("../command_summary.zig");
const UNAVAILABLE_WORKSPACE_SENTINEL = "/__nullclaw_workspace_unavailable__";
const log = std.log.scoped(.shell);

/// Default maximum shell command execution time (nanoseconds).
const DEFAULT_SHELL_TIMEOUT_NS: u64 = 60 * std.time.ns_per_s;
/// Default maximum output size in bytes (1MB).
const DEFAULT_MAX_OUTPUT_BYTES: usize = 1_048_576;
/// Environment variables safe to pass to shell commands.

fn safeEnvVarAllowed(key: []const u8) bool

/// Validate that a platform path-list value has all components within
/// the sandbox (workspace + allowed_paths). Uses the same validation as
/// file access: system blocklist always rejects, then workspace and
/// allowed_paths are checked via realpath canonicalization.
/// Platform-aware path-list delimiter: `;` on Windows, `:` elsewhere.
const path_list_delimiter: u8 = if (@import("builtin").os.tag == .windows) ';' else ':';

    var iter = std.mem.splitScalar(u8, value, path_list_delimiter);
        // Must be absolute
        // Resolve to canonical path (follows symlinks)

fn normalizeCommandInput(command: []const u8) []const u8

fn unwrapMarkdownFence(command: []const u8) ?[]const u8

/// Shell command execution tool with workspace scoping.
pub const ShellTool = struct {
    /// Env var names whose platform path-list values are validated
    /// against workspace + allowed_paths before passing to child processes.

/// Extract a string field value from a JSON blob (minimal parser — no allocations).
/// NOTE: Prefer root.getString() with pre-parsed ObjectMap for tool implementations.
pub fn parseStringField(json: []const u8, key: []const u8) ?[]const u8

/// Extract a boolean field value from a JSON blob.
pub fn parseBoolField(json: []const u8, key: []const u8) ?bool

fn parseWindowsCommandArgv(allocator: std.mem.Allocator, command: []const u8) ![]const []const u8

fn freeOwnedArgv(allocator: std.mem.Allocator, argv: []const []const u8) void

fn windowsBasename(path: []const u8) []const u8

fn isPowerShellExecutable(executable: []const u8) bool

/// Extract an integer field value from a JSON blob.
pub fn parseIntField(json: []const u8, key: []const u8) ?i64

// ── Tests ───────────────────────────────────────────────────────────

test "parseWindowsCommandArgv preserves PowerShell flags and quoted script" {


test "isPowerShellExecutable requires exact basename match" {


test "shell tool name" {
    var st = ShellTool{

test "shell tool schema has command" {
    var st = ShellTool{

test "shell executes echo" {
    var st = ShellTool{

test "shell captures failing command" {
    var st = ShellTool{

test "shell reports interruption when cancel flag is set" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    var st = ShellTool{

test "shell missing command param" {
    var st = ShellTool{

test "shell safe env keeps required Windows variables" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;


test "parseStringField basic" {
    const json = "{

test "parseStringField missing" {
    const json = "{

test "parseBoolField true" {
    const json = "{

test "parseBoolField false" {
    const json = "{

test "parseIntField positive" {
    const json = "{

test "parseIntField negative" {
    const json = "{

test "shell cwd inside workspace works without allowed_paths" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest; // pwd not available on Windows

    var tmp_dir = std.testing.tmpDir(.{

test "shell cwd outside workspace without allowed_paths is rejected" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest; // pwd not available on Windows

    var tmp_dir = std.testing.tmpDir(.{

test "shell cwd relative path is rejected" {
    var st = ShellTool{

test "shell cwd with allowed_paths runs in cwd" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest; // pwd not available on Windows

    var tmp_dir = std.testing.tmpDir(.{

test "shell ApprovalRequired error includes command name" {
    const policy_mod = @import("../security/policy.zig");
    var tracker = policy_mod.RateTracker.init(std.testing.allocator, 100);
    const allowed = [_][]const u8{

test "shell ApprovalRequired propagates oom for error message allocation" {
    const policy_mod = @import("../security/policy.zig");
    var tracker = policy_mod.RateTracker.init(std.testing.allocator, 100);
    const allowed = [_][]const u8{

test "shell wildcard policy permits command outside default allowlist" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    const policy_mod = @import("../security/policy.zig");
    var restrictive_tracker = policy_mod.RateTracker.init(std.testing.allocator, 10000);

    var restrictive_tool = ShellTool{

test "shell wildcard policy allows stderr redirect to dev null" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    const policy_mod = @import("../security/policy.zig");
    var tracker = policy_mod.RateTracker.init(std.testing.allocator, 10000);

    var st = ShellTool{

test "shell accepts markdown-fenced command payload" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    const policy_mod = @import("../security/policy.zig");
    var tracker = policy_mod.RateTracker.init(std.testing.allocator, 1000);

    var st = ShellTool{

test "shell keeps subshell backticks blocked after fenced markdown normalization" {
    const policy_mod = @import("../security/policy.zig");
    var tracker = policy_mod.RateTracker.init(std.testing.allocator, 1000);

    var st = ShellTool{

test "shell without policy executes command" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    var st = ShellTool{

test "validatePathEnvValue allows paths within workspace" {
    var tmp_dir = std.testing.tmpDir(.{

test "validatePathEnvValue allows delimiter-separated paths within workspace" {
    var tmp_dir = std.testing.tmpDir(.{

test "validatePathEnvValue rejects paths outside workspace" {
    var tmp_dir = std.testing.tmpDir(.{

test "validatePathEnvValue rejects system paths" {
    const system_path = if (@import("builtin").os.tag == .windows) "C:\\Windows\\System32" else "/usr/lib";
    const fake_ws = if (@import("builtin").os.tag == .windows) "C:\\Users\\test\\workspace" else "/home/user/workspace";

test "validatePathEnvValue allows via allowed_paths" {
    var tmp_dir = std.testing.tmpDir(.{

test "validatePathEnvValue rejects mixed valid and invalid paths" {
    var tmp_dir = std.testing.tmpDir(.{

test "validatePathEnvValue rejects relative paths" {
    const fake_ws = if (@import("builtin").os.tag == .windows) "C:\\Users\\test\\workspace" else "/home/user/workspace";

test "validatePathEnvValue allows empty value" {
    const fake_ws = if (@import("builtin").os.tag == .windows) "C:\\Users\\test\\workspace" else "/home/user/workspace";

test "shell path_env_vars passes validated vars to child" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp_dir = std.testing.tmpDir(.{
