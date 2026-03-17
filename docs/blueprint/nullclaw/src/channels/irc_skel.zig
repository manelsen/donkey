const std = @import("std");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const bus_mod = @import("../bus.zig");
const thread_stacks = @import("../thread_stacks.zig");

const log = std.log.scoped(.irc);

/// IRC style prefix prepended to messages before they reach the LLM.

/// Max nick collision retries before giving up.
const MAX_NICK_RETRIES: usize = 5;

/// IRC service bot names to filter out.
const SERVICE_BOTS = [_][]const u8{