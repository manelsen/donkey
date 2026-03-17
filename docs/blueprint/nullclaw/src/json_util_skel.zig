//! Shared JSON string utilities (RFC 8259).
//!
//! Replaces 10+ local `appendJsonString` duplicates across the codebase.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Append a JSON-escaped string (with enclosing quotes) to the buffer.
/// Handles: `"`, `\`, `\n`, `\r`, `\t`, control chars < 0x20 → `\u00XX`.
pub fn appendJsonString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, s: []const u8) !void

/// Append `"key":` (JSON-escaped key with colon) to the buffer.
pub fn appendJsonKey(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, key: []const u8) !void

/// Append `"key":"value"` (both JSON-escaped) to the buffer.
pub fn appendJsonKeyValue(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, key: []const u8, value: []const u8) !void

/// Append `"key":123` (JSON-escaped key, integer value) to the buffer.
pub fn appendJsonInt(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, key: []const u8, value: i64) !void

// ── Tests ───────────────────────────────────────────────────────────

test "appendJsonString empty string" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonString plain ASCII" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonString escapes quotes" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonString escapes backslash" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonString escapes tabs and newlines" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonString escapes control chars" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonString preserves Unicode" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonKeyValue" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonInt" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;

test "appendJsonInt negative" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
