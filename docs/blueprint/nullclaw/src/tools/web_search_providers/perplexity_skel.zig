const std = @import("std");
const common = @import("common.zig");

    const timeout_str = try common.timeoutToString(allocator, timeout_secs);

    const endpoint = "https://api.perplexity.ai/search";
    const auth_header = try std.fmt.allocPrint(allocator, "Authorization: Bearer{
