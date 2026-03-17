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

/// Default maximum file size to read (10MB).
const DEFAULT_MAX_FILE_SIZE: u64 = 10 * 1024 * 1024;

/// Binary file signature entry
const BinarySignature = struct {

/// Known binary file signatures (magic numbers) with type names

/// Extension to type name mapping (fallback when magic number not detected)

fn isWebP(data: []const u8) bool

fn hasIsoBmffHeader(data: []const u8) bool

pub fn isBinaryContent(data: []const u8) bool

pub fn getBinaryFileType(data: []const u8, path: []const u8) []const u8

/// Read file contents with workspace path scoping.
pub const FileReadTool = struct {

fn resolveNearestExistingAncestor(allocator: std.mem.Allocator, path: []const u8) ![]const u8

fn bootstrapRootFilename(path: []const u8) ?[]const u8

// ── Tests ───────────────────────────────────────────────────────────

test "file_read tool name" {
    var ft = FileReadTool{

test "file_read tool schema has path" {
    var ft = FileReadTool{

test "file_read reads existing file" {
    // Create temp dir and file
    var tmp_dir = std.testing.tmpDir(.{

test "file_read nonexistent file" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_read blocks path traversal" {
    var ft = FileReadTool{

test "file_read blocks absolute path" {
    var ft = FileReadTool{

test "file_read missing path param" {
    var ft = FileReadTool{

test "file_read nested path" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_read empty file" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_read reads bootstrap doc from memory backend" {
    var tmp_dir = std.testing.tmpDir(.{

test "isPathSafe blocks null bytes" {

test "isPathSafe allows relative" {

test "file_read absolute path without allowed_paths is rejected" {
    var ft = FileReadTool{

test "file_read absolute path with allowed_paths works" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_read reports PNG files as binary" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_read reports WAV files as WAV instead of WebP" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_read reports WebP files as WebP" {
    var tmp_dir = std.testing.tmpDir(.{

test "file_read reports HEIC files as HEIC instead of MP4" {
    var tmp_dir = std.testing.tmpDir(.{
