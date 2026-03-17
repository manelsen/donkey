const std = @import("std");
const net_security = @import("net_security.zig");

pub const Error = std.mem.Allocator.Error || error{