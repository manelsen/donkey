const std = @import("std");
const fs_compat = @import("../fs_compat.zig");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const isPathSafe = @import("path_security.zig").isPathSafe;
const isResolvedPathAllowed = @import("path_security.zig").isResolvedPathAllowed;
const generateLineHash = @import("file_read_hashed.zig").generateLineHash;

const RADIUS: usize = 50;


fn findLineWithRadius(lines: []const LineInfo, hint_idx: usize, target_hash: []const u8) LineSearchResult

/// Default maximum file size to read (10MB).
const DEFAULT_MAX_FILE_SIZE: usize = 10 * 1024 * 1024;

const Target = struct {

const LineInfo = struct {

fn collectLines(allocator: std.mem.Allocator, contents: []const u8, lines: *std.ArrayList(LineInfo)) !void

/// Edit file contents using Hashline anchors for verifiable changes.
pub const FileEditHashedTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "file_edit_hashed replaces line when hash matches with shift" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit_hashed rejects ambiguous collision during shift" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit_hashed fails when hash mismatches" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit_hashed preserves missing trailing newline at eof" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_edit_hashed rejects absolute path outside allowed areas" {
    var ws_tmp = std.testing.tmpDir(.{
