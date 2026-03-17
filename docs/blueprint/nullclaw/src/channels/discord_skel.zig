const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const bus_mod = @import("../bus.zig");
const websocket = @import("../websocket.zig");
const thread_stacks = @import("../thread_stacks.zig");

const Atomic = @import("../portable_atomic.zig").Atomic;

const log = std.log.scoped(.discord);

/// Discord channel — connects via WebSocket gateway, sends via REST API.
/// Splits messages at 2000 chars (Discord limit).
pub const DiscordChannel = struct {
    // Optional gateway fields (have defaults so existing init works)
    // Gateway state