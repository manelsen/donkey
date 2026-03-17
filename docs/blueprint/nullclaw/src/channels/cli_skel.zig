const std = @import("std");
const platform = @import("../platform.zig");
const root = @import("root.zig");

/// CLI channel — reads from stdin, writes to stdout.
/// Simplest channel implementation; used for local interactive testing.
pub const CliChannel = struct {

// ═══════════════════════════════════════════════════════════════════════════
// History — persistent REPL command history (~/.nullclaw_history)
// ═══════════════════════════════════════════════════════════════════════════

const MAX_HISTORY_LINES: usize = 500;

/// Load command history from a file (one command per line).
/// Returns up to MAX_HISTORY_LINES most recent entries.
/// If the file does not exist, returns an empty slice.
/// Caller owns the returned slice and all strings within it.
pub fn loadHistory(allocator: std.mem.Allocator, path: []const u8) ![][]const u8

/// Free history entries returned by loadHistory.
pub fn freeHistory(allocator: std.mem.Allocator, history: [][]const u8) void

/// Save command history to a file (one command per line).
/// Writes at most MAX_HISTORY_LINES entries.
pub fn saveHistory(history: []const []const u8, path: []const u8) !void

/// Resolve the default history file path (~/.nullclaw_history).
/// Caller owns the returned string.
pub fn defaultHistoryPath(allocator: std.mem.Allocator) ![]const u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "cli quit commands" {

test "loadHistory reads file lines" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "loadHistory returns empty for missing file" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "saveHistory writes file" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "saveHistory and loadHistory roundtrip" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "loadHistory trims whitespace from entries" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "loadHistory skips blank lines" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "loadHistory enforces max entries limit" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "MAX_HISTORY_LINES is 500" {
