//! File Append Tool — append content to the end of a file within workspace.
//!
//! Creates the file if it doesn't exist. Uses workspace path scoping
//! and the same path safety checks as file_edit.

const std = @import("std");
const fs_compat = @import("../fs_compat.zig");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const isPathSafe = @import("path_security.zig").isPathSafe;
const isResolvedPathAllowed = @import("path_security.zig").isResolvedPathAllowed;

/// Default maximum file size to read before appending (10MB).
const DEFAULT_MAX_FILE_SIZE: usize = 10 * 1024 * 1024;

/// Append content to the end of a file with workspace path scoping.
pub const FileAppendTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "FileAppendTool name and description" {
    var fat = FileAppendTool{