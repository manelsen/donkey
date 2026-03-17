const std = @import("std");
const builtin = @import("builtin");
const fs_compat = @import("../fs_compat.zig");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const isPathSafe = @import("path_security.zig").isPathSafe;
const isResolvedPathAllowed = @import("path_security.zig").isResolvedPathAllowed;
const bootstrap_mod = @import("../bootstrap/root.zig");
const memory_root = @import("../memory/root.zig");

/// Write file contents with workspace path scoping.
pub const FileWriteTool = struct {

fn resolveNearestExistingAncestor(allocator: std.mem.Allocator, path: []const u8) ![]const u8

fn bootstrapRootFilename(path: []const u8) ?[]const u8

fn isSymlinkPath(path: []const u8) !bool

// ── Tests ───────────────────────────────────────────────────────────

test "file_write tool name" {
    var ft = FileWriteTool{

test "file_write tool schema has path and content" {
    var ft = FileWriteTool{

test "file_write creates file" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_write creates parent dirs" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_write overwrites existing" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_write blocks path traversal" {
    var ft = FileWriteTool{

test "file_write blocks absolute path" {
    var ft = FileWriteTool{

test "file_write missing path param" {
    var ft = FileWriteTool{

test "file_write missing content param" {
    var ft = FileWriteTool{

test "file_write empty content" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_write blocks symlink target escape outside workspace" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    var ws_tmp = std.testing.tmpDir(.{

test "file_write does not mutate outside inode through hard link" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    var ws_tmp = std.testing.tmpDir(.{

test "file_write keeps symlink and updates target" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    var ws_tmp = std.testing.tmpDir(.{

test "file_write preserves executable mode on overwrite" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    var ws_tmp = std.testing.tmpDir(.{

test "file_write rejects disallowed absolute path without creating parent directories" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    var ws_tmp = std.testing.tmpDir(.{

test "file_write does not bypass allowed_paths for bootstrap memory writes" {
    var ws_tmp = std.testing.tmpDir(.{
