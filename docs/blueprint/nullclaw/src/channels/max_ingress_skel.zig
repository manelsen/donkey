//! Update parser for the Max messenger Bot API.
//!
//! Converts raw JSON updates from the Max Bot API into typed Zig structs
//! for the MaxChannel to process. Handles message_created, message_callback,
//! bot_started, and other update types.

const std = @import("std");

// ════════════════════════════════════════════════════════════════════════════
// Update Types
// ════════════════════════════════════════════════════════════════════════════

pub const UpdateType = enum {

// ════════════════════════════════════════════════════════════════════════════
// Parsed Update Structures
// ════════════════════════════════════════════════════════════════════════════

pub const ChatType = enum { dialog, chat, channel };