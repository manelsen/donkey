const std = @import("std");
const builtin = @import("builtin");

fn capped_read_limit(max_bytes: u64) usize

/// Compatibility wrapper for `Dir.readFileAlloc` that avoids Zig 0.15.2's
/// `File.stat()` path on Linux kernels where `statx` is unavailable.
pub fn readFileAlloc(dir: std.fs.Dir, allocator: std.mem.Allocator, sub_path: []const u8, max_bytes: u64) ![]u8

/// Compatibility wrapper for `File.stat()` that uses `fstat` on POSIX
/// platforms instead of the Linux `statx` fast path in Zig 0.15.2.
pub fn stat(file: std.fs.File) std.fs.File.StatError!std.fs.File.Stat

test "readFileAlloc reads file contents" {
    var tmp_dir = std.testing.tmpDir(.{

test "stat returns file size" {
    var tmp_dir = std.testing.tmpDir(.{
