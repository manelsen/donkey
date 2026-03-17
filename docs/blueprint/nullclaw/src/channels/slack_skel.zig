const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const interaction_choices = @import("../interactions/choices.zig");
const bus_mod = @import("../bus.zig");
const websocket = @import("../websocket.zig");

const Atomic = @import("../portable_atomic.zig").Atomic;

const log = std.log.scoped(.slack);

const SocketFd = std.net.Stream.Handle;

const CALLBACK_VALUE_PREFIX = "ncslack:";
const DEFAULT_INTERACTION_TTL_SECS: u64 = 900;

const PendingInteractionOption = struct {

const PendingInteraction = struct {


var shared_interactions_mu: std.Thread.Mutex = .{