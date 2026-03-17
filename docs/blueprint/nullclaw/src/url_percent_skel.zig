const std = @import("std");

pub fn isUnreserved(c: u8) bool

pub fn appendPercentEncodedWriter(writer: anytype, text: []const u8) !void

            const upper = "0123456789ABCDEF";

pub fn encode(allocator: std.mem.Allocator, text: []const u8) ![]u8

test "url_percent encode leaves unreserved as-is" {
    const alloc = std.testing.allocator;
    const encoded = try encode(alloc, "hello-world_2.0~test");

test "url_percent encode percent-encodes reserved bytes" {
    const alloc = std.testing.allocator;
    const encoded = try encode(alloc, "a b/c?");

test "url_percent appendPercentEncodedWriter percent-encodes bytes" {
    var out: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out);
