const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");

/// Component health status.
pub const ComponentHealth = struct {

/// Full health snapshot.
pub const HealthSnapshot = struct {

/// Global health registry — thread-safe singleton.
var registry_mutex: std.Thread.Mutex = .{