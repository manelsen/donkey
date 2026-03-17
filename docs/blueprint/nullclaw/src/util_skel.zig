const std = @import("std");

/// Format bytes as human-readable string (e.g. "3.4 MB")
pub fn formatBytes(bytes: u64) struct

/// Get current timestamp as ISO 8601 string
pub fn timestamp(buf: []u8) []const u8

test "formatBytes" {
    const result = formatBytes(3_500_000);

test "timestamp produces valid length" {
    var buf: [32]u8 = undefined;
    const ts = timestamp(&buf);

// ── JSON helpers ────────────────────────────────────────────────

/// Append a string to an ArrayList with JSON escaping (quotes, backslashes, control chars).
/// Used by embedding providers, vector stores, and API backends when building JSON payloads.
pub fn appendJsonEscaped(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, text: []const u8) !void

// ── Additional util tests ───────────────────────────────────────

test "formatBytes zero" {
    const result = formatBytes(0);

test "formatBytes exact KB" {
    const result = formatBytes(1024);

test "formatBytes exact MB" {
    const result = formatBytes(1024 * 1024);

test "formatBytes exact GB" {
    const result = formatBytes(1024 * 1024 * 1024);

test "formatBytes exact TB" {
    const result = formatBytes(1024 * 1024 * 1024 * 1024);

test "formatBytes small value stays in bytes" {
    const result = formatBytes(500);

test "formatBytes 1 byte" {
    const result = formatBytes(1);

test "formatBytes large value" {
    const result = formatBytes(5 * 1024 * 1024 * 1024 * 1024);

test "timestamp ends with Z" {
    var buf: [32]u8 = undefined;
    const ts = timestamp(&buf);

test "timestamp contains T separator" {
    var buf: [32]u8 = undefined;
    const ts = timestamp(&buf);

test "appendJsonEscaped basic text" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonEscaped escapes special chars" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonEscaped escapes control chars" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonEscaped empty string" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
