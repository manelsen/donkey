const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const bus = @import("bus.zig");
const fs_compat = @import("fs_compat.zig");
const json_util = @import("json_util.zig");
const Config = @import("config.zig").Config;

const log = std.log.scoped(.cron);

pub const JobType = enum {

pub const SessionTarget = enum {

pub const ScheduleKind = enum { cron, at, every };