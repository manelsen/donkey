//! Path security helpers shared by file_read, file_write, file_edit, file_append,
//! shell, and git tools.
//!
//! Extracted from file_edit.zig to eliminate cross-imports between tool files.

const std = @import("std");
const path_prefix = @import("../path_prefix.zig");

/// System-critical prefixes (Unix) — always blocked even if they match allowed_paths.

/// System-critical prefixes (Windows).

/// Platform-selected system blocked prefixes.

/// Check whether a directory-style prefix matches (exact or followed by a path separator).
pub fn pathStartsWith(path: []const u8, prefix: []const u8) bool

/// Check whether a **resolved** absolute path is allowed by the policy:
///  1. System blocklist always rejects.
///  2. Workspace prefix matches → allowed.
///  3. Any allowed_path prefix matches (resolved on the fly) → allowed.
    // 1. System blocklist
    // 2. Workspace
    // 3. Allowed paths (resolve each to handle symlinks)
        const ap = std.mem.trim(u8, raw_allowed_path, " \t\r\n");
        const ap_resolved = std.fs.cwd().realpathAlloc(allocator, ap) catch continue;

/// Check if a relative path is safe (no traversal, no absolute path).
pub fn isPathSafe(path: []const u8) bool

// ── Tests ───────────────────────────────────────────────────────────

test "isPathSafe blocks null bytes" {

test "isPathSafe allows relative" {

test "isPathSafe blocks traversal" {

test "isPathSafe blocks absolute" {

test "isPathSafe blocks URL-encoded traversal" {
    // Case-insensitive

test "isPathSafe allows percent in non-traversal context" {

test "isResolvedPathAllowed allows workspace path" {

test "isResolvedPathAllowed allows exact workspace" {

test "isResolvedPathAllowed rejects outside workspace" {

test "isResolvedPathAllowed rejects partial prefix match" {

test "isResolvedPathAllowed blocks system paths" {
    if (comptime @import("builtin").os.tag == .windows) {

test "isResolvedPathAllowed allows via allowed_paths" {
    var tmp_dir = std.testing.tmpDir(.{

test "isResolvedPathAllowed wildcard allows non-system paths" {

test "isResolvedPathAllowed wildcard with whitespace allows non-system paths" {

test "isResolvedPathAllowed trims allowed path entries before resolving" {
    var tmp_dir = std.testing.tmpDir(.{

test "isResolvedPathAllowed wildcard does not bypass system blocklist" {
    if (comptime @import("builtin").os.tag == .windows) {

test "pathStartsWith exact match" {

test "pathStartsWith with trailing component" {

test "pathStartsWith windows is case-insensitive" {
    if (comptime @import("builtin").os.tag != .windows) return;

test "pathStartsWith windows accepts mixed separators and verbatim prefix" {
    if (comptime @import("builtin").os.tag != .windows) return;

test "pathStartsWith rejects partial" {
