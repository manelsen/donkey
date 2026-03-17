const std = @import("std");
const platform = @import("../platform.zig");
const codex_support = @import("../codex_support.zig");
const root = @import("root.zig");

const Provider = root.Provider;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;
const ChatMessage = root.ChatMessage;

/// Provider that delegates to the local `codex` CLI.
///
/// Runs `codex exec` non-interactively and reads the final assistant message
/// from the `--output-last-message` file.
pub const CodexCliProvider = struct {

// ════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ════════════════════════════════════════════════════════════════════════════

/// Resolve the codex CLI and ensure it exists.
fn checkCliAvailable(allocator: std.mem.Allocator) !void

/// Run `codex --version` and verify exit code 0.
fn checkCliVersion(allocator: std.mem.Allocator) !void

fn effectiveModel(requested_model: []const u8, configured_model: []const u8) []const u8

fn makeOutputPath(allocator: std.mem.Allocator) ![]u8

/// Extract the content of the last user message from a message slice.
fn extractLastUserMessage(messages: []const ChatMessage) ?[]const u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "CodexCliProvider.getNameImpl returns codex-cli" {
    const vtable = CodexCliProvider.vtable;
    var dummy: u8 = 0;

test "CodexCliProvider vtable has correct function pointers" {
    const vtable = CodexCliProvider.vtable;
    var dummy: u8 = 0;

test "CodexCliProvider supportsNativeTools returns false" {
    const vtable = CodexCliProvider.vtable;
    var dummy: u8 = 0;

test "effectiveModel prefers explicit override" {

test "effectiveModel falls back to configured model" {

test "extractLastUserMessage finds last user" {
    const result = extractLastUserMessage(&msgs);

test "extractLastUserMessage returns null for no user" {

test "extractLastUserMessage empty messages" {
    const msgs = [_]ChatMessage{

test "CodexCliProvider default model is gpt-5.4" {
