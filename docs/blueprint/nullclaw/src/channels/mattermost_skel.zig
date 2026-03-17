const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const websocket = @import("../websocket.zig");
const bus_mod = @import("../bus.zig");
const config_types = @import("../config_types.zig");
const url_percent = @import("../url_percent.zig");
const thread_stacks = @import("../thread_stacks.zig");

const Atomic = @import("../portable_atomic.zig").Atomic;

const log = std.log.scoped(.mattermost);

const SocketFd = std.net.Stream.Handle;

const DEFAULT_ONCHAR_PREFIXES = [_][]const u8{