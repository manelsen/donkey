const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const verbose = @import("../verbose.zig");
const log = std.log.scoped(.screenshot);

/// Screenshot tool — capture the screen using platform-native commands.
/// macOS: `screencapture -x FILE`
/// Linux: `import FILE` (ImageMagick)
/// Windows: PowerShell-based screen capture
pub const ScreenshotTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "screenshot tool name" {
    var st = ScreenshotTool{

test "screenshot tool schema has filename" {
    var st = ScreenshotTool{

test "screenshot execute returns mock in test mode" {
    const allocator = std.testing.allocator;
    var st = ScreenshotTool{

test "screenshot execute with custom filename" {
    const allocator = std.testing.allocator;
    var st = ScreenshotTool{
