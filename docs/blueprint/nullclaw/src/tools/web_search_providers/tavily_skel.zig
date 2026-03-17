const std = @import("std");
const common = @import("common.zig");

    const timeout_str = try common.timeoutToString(allocator, timeout_secs);

    const endpoint = "https://api.tavily.com/search";
    const body_json = try std.json.Stringify.valueAlloc(allocator, payload, .{
