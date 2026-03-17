const std = @import("std");
const fs_compat = @import("../fs_compat.zig");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const isPathSafe = @import("path_security.zig").isPathSafe;
const isResolvedPathAllowed = @import("path_security.zig").isResolvedPathAllowed;
const bootstrap_mod = @import("../bootstrap/root.zig");
const memory_root = @import("../memory/root.zig");

/// Default maximum file size to read for editing (10MB).
const DEFAULT_MAX_FILE_SIZE: usize = 10 * 1024 * 1024;

/// Find and replace text in a file with workspace path scoping.
pub const FileEditTool = struct {

fn resolveNearestExistingAncestor(allocator: std.mem.Allocator, path: []const u8) ![]const u8

fn bootstrapRootFilename(path: []const u8) ?[]const u8

// ── Tests ───────────────────────────────────────────────────────────

test "file_edit tool name" {
    var ft = FileEditTool{

test "file_edit tool schema has required params" {
    var ft = FileEditTool{

test "file_edit basic replace" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit old_text not found" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit nonexistent file error includes requested path" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit empty file returns not found" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit replaces only first occurrence" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit blocks path traversal" {
    var ft = FileEditTool{

test "file_edit missing path param" {
    var ft = FileEditTool{

test "file_edit missing old_text param" {
    var ft = FileEditTool{

test "file_edit missing new_text param" {
    var ft = FileEditTool{

test "file_edit empty old_text" {
    var tmp_dir = std.testing.tmpDir(.{

// ── Absolute path support tests ─────────────────────────────────────

test "file_edit absolute path without allowed_paths is rejected" {
    var ft = FileEditTool{

test "file_edit absolute path with allowed_paths works" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit does not bypass allowed_paths for bootstrap memory edits" {
    var ws_tmp = std.testing.tmpDir(.{
