const std = @import("std");
const common = @import("common.zig");

    const timeout_str = try common.timeoutToString(allocator, timeout_secs);

    const endpoint = "https://api.exa.ai/search";
    const key_header = try std.fmt.allocPrint(allocator, "x-api-key:{
