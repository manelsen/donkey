const std = @import("std");
const common = @import("common.zig");

    const encoded_query = try common.urlEncodePath(allocator, query);

    const url_str = try std.fmt.allocPrint(allocator, "https://s.jina.ai/{

fn isApiErrorPayload(allocator: std.mem.Allocator, body: []const u8) bool