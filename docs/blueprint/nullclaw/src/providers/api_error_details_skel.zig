const std = @import("std");

const MAX_PROVIDER_BYTES: usize = 64;
const MAX_DETAIL_BYTES: usize = 2048;

var mutex: std.Thread.Mutex = .{