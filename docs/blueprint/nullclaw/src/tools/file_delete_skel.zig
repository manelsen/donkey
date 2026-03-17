const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const isPathSafe = @import("path_security.zig").isPathSafe;
const isResolvedPathAllowed = @import("path_security.zig").isResolvedPathAllowed;
const bootstrap_mod = @import("../bootstrap/root.zig");
const onboard = @import("../onboard.zig");

/// Delete BOOTSTRAP.md from the workspace or bootstrap memory backend.
pub const FileDeleteTool = struct {

fn resolveNearestExistingAncestor(allocator: std.mem.Allocator, path: []const u8) ![]const u8

test "file_delete tool name" {
    var ft = FileDeleteTool{

test "file_delete rejects non-bootstrap paths" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_delete removes sqlite bootstrap and marks onboarding complete" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_delete removes sqlite bootstrap disk fallback when DB entry is absent" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_delete removes sqlite bootstrap from DB and disk fallback together" {
    var tmp_dir = std.testing.tmpDir(.{
