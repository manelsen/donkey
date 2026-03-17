const std = @import("std");
const common = @import("common.zig");

    const encoded_query = try common.urlEncode(allocator, query);


    const timeout_str = try common.timeoutToString(allocator, timeout_secs);

    const auth_header = try std.fmt.allocPrint(allocator, "X-Subscription-Token:{

pub fn formatResults(allocator: std.mem.Allocator, json_body: []const u8, query: []const u8) !common.ToolResult
