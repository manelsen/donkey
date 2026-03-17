const std = @import("std");
const Config = @import("config.zig").Config;
const version = @import("version.zig");
const channel_catalog = @import("channel_catalog.zig");

pub fn run(allocator: std.mem.Allocator) !void
