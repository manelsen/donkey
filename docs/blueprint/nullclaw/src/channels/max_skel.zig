//! Max messenger channel — uses the Max Bot API with long-polling or webhooks.
//!
//! Implements the Channel vtable interface for the Max (VK Teams successor)
//! messaging platform. Supports inline keyboards, draft streaming via
//! message editing, typing indicators, and attachment forwarding.

const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const interaction_choices = @import("../interactions/choices.zig");
const max_api = @import("max_api.zig");
const max_ingress = @import("max_ingress.zig");
const thread_stacks = @import("../thread_stacks.zig");
const streaming = @import("../streaming.zig");
const Atomic = @import("../portable_atomic.zig").Atomic;

const log = std.log.scoped(.max);

// ════════════════════════════════════════════════════════════════════════════
// Constants
// ════════════════════════════════════════════════════════════════════════════

pub const MAX_MESSAGE_LEN: usize = 4000;
const CONTINUATION_MARKER = "\n\n\u{