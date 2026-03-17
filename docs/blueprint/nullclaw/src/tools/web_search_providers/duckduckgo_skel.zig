const std = @import("std");
const common = @import("common.zig");

    const encoded_query = try common.urlEncode(allocator, query);


    const timeout_str = try common.timeoutToString(allocator, timeout_secs);



    const result = try formatResults(allocator, body, query, count);

pub fn formatResults(allocator: std.mem.Allocator, json_body: []const u8, query: []const u8, count: usize) !common.ToolResult



        const text = common.extractString(topic_obj, "Text");
        const first_url = common.extractString(topic_obj, "FirstURL");


