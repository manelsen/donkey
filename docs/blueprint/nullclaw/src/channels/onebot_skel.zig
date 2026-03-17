const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const bus = @import("../bus.zig");
const websocket = @import("../websocket.zig");
const thread_stacks = @import("../thread_stacks.zig");
const Atomic = @import("../portable_atomic.zig").Atomic;

const log = std.log.scoped(.onebot);

const SocketFd = std.net.Stream.Handle;

// ════════════════════════════════════════════════════════════════════════════
// CQ Code Parsing
// ════════════════════════════════════════════════════════════════════════════

/// Result of parsing CQ-coded message text.
pub const CqParseResult = struct {
    /// Plain text with all CQ tags removed.
    /// Whether the message contains a mention ([CQ:at,...]).
    /// Mentioned QQ number (from [CQ:at,qq=...]), null if no mention.
    /// Media URLs/files extracted from [CQ:image,...] tags.
    /// Reply message ID from [CQ:reply,id=...], null if not a reply.

/// Parse CQ-coded message text, extracting tags and returning clean text.
///
/// Supported CQ tags:
///   [CQ:image,file=xxx]   -> media attachment
///   [CQ:at,qq=123456]     -> mention (sets is_mention)
///   [CQ:reply,id=xxx]     -> reply to message
///   [CQ:face,id=xxx]      -> stripped (emoji)
///   Other [CQ:...] tags   -> stripped
pub fn parseCqTags(allocator: std.mem.Allocator, raw: []const u8) !CqParseResult

/// Extract a parameter value from CQ tag params string.
/// E.g. extractParam("file=abc.jpg,cache=1", "file") -> "abc.jpg"
fn extractParam(params: []const u8, key: []const u8) ?[]const u8

// ════════════════════════════════════════════════════════════════════════════
// Message Deduplication
// ════════════════════════════════════════════════════════════════════════════

pub const DEDUP_RING_SIZE: usize = 1024;

/// Ring buffer for message_id deduplication.
/// Stores the last DEDUP_RING_SIZE message IDs in a circular buffer.
pub const DedupRing = struct {
    /// Check if message_id was already seen. If not, record it and return false.
    /// Returns true if the message is a duplicate.

// ════════════════════════════════════════════════════════════════════════════
// OneBotChannel
// ════════════════════════════════════════════════════════════════════════════

/// OneBot v11 protocol channel.
///
/// Connects to a OneBot v11 implementation (go-cqhttp, NapCat, Lagrange, etc.)
/// via WebSocket or HTTP API. Receives messages, parses CQ codes, publishes
/// to the event bus. Sends outgoing messages via HTTP POST to /send_msg.
pub const OneBotChannel = struct {