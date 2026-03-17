const std = @import("std");
const fs_compat = @import("../fs_compat.zig");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const isPathSafe = @import("path_security.zig").isPathSafe;
const isResolvedPathAllowed = @import("path_security.zig").isResolvedPathAllowed;
const getBinaryFileType = @import("file_read.zig").getBinaryFileType;
const isBinaryContent = @import("file_read.zig").isBinaryContent;

/// Default maximum file size to read (10MB).
const DEFAULT_MAX_FILE_SIZE: u64 = 10 * 1024 * 1024;

/// Generate a 3-character hex hash for a line, including parent context.
pub fn generateLineHash(parent: []const u8, current: []const u8) [3]u8

/// Read file contents with Hashline tagging (L<num>:<hash>| content).
pub const FileReadHashedTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "generateLineHash is context-aware" {
    const h1 = generateLineHash("parent1", "child");
    const h2 = generateLineHash("parent2", "child");
    const h3 = generateLineHash("parent1", "child");


test "file_read_hashed adds tags to lines" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_read_hashed reports binary files like file_read" {
    var tmp_dir = std.testing.tmpDir(.{
