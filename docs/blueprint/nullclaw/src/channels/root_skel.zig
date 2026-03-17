//! Channels — messaging platform integrations.
//! Each channel implements the Channel interface (vtable-based polymorphism).
//!
//! Channels (matching ZeroClaw):
//!   - CLI (built-in stdin/stdout)
//!   - Telegram (long-polling)
//!   - Discord (WebSocket gateway)
//!   - Slack (socket/http event pipeline)
//!   - WhatsApp (webhook-based)
//!   - Matrix (long-polling /sync)
//!   - Mattermost (WebSocket + REST API)
//!   - IRC (TLS socket)
//!   - iMessage (AppleScript + SQLite on macOS)
//!   - Email (IMAP/SMTP)
//!   - Lark/Feishu (HTTP callback)
//!   - DingTalk (WebSocket stream mode)

const std = @import("std");
const streaming = @import("../streaming.zig");
const outbound = @import("../outbound.zig");

// ════════════════════════════════════════════════════════════════════════════
// Shared Types
// ════════════════════════════════════════════════════════════════════════════

/// A message received from or sent to a channel.
pub const ChannelMessage = struct {
    /// Where to send a reply (e.g., DM sender vs channel name in IRC, thread ID in Telegram).
    /// Platform message ID (e.g. Telegram message_id for reply-to).
    /// Sender's first name (for personalized greetings).
    /// Whether the message came from a group chat.
    /// Sender UUID (Signal-specific: when user has privacy mode enabled).
    /// Group ID (Signal-specific: for group chats).

/// Channel interface — Zig equivalent of ZeroClaw's Channel trait.
/// Uses vtable-based polymorphism for runtime dispatch.
pub const Channel = struct {

// ════════════════════════════════════════════════════════════════════════════
// Channel Sub-modules
// ════════════════════════════════════════════════════════════════════════════

pub const cli = @import("cli.zig");
pub const telegram = @import("telegram.zig");
pub const discord = @import("discord.zig");
pub const slack = @import("slack.zig");
pub const whatsapp = @import("whatsapp.zig");
pub const teams = @import("teams.zig");
pub const matrix = @import("matrix.zig");
pub const mattermost = @import("mattermost.zig");
pub const irc = @import("irc.zig");
pub const imessage = @import("imessage.zig");
pub const email = @import("email.zig");
pub const lark = @import("lark.zig");
pub const dingtalk = @import("dingtalk.zig");
pub const nostr = @import("nostr.zig");
pub const line = @import("line.zig");
pub const onebot = @import("onebot.zig");
pub const qq = @import("qq.zig");
pub const maixcam = @import("maixcam.zig");
pub const signal = @import("signal.zig");
        pub const WebChannel = struct {
        pub const MaxChannel = struct {

        pub fn setInteractiveOwnerContext(_: ?[]const u8) void
pub const dispatch = @import("dispatch.zig");

// ════════════════════════════════════════════════════════════════════════════
// Utility
// ════════════════════════════════════════════════════════════════════════════

/// Split a message at `max_bytes`, respecting UTF-8 char boundaries.
/// Returns slices into the original `msg` buffer.
pub fn splitMessage(msg: []const u8, max_bytes: usize) SplitIterator

pub const SplitIterator = struct {

// ════════════════════════════════════════════════════════════════════════════
// Per-Channel Permission Policies
// ════════════════════════════════════════════════════════════════════════════

/// DM (direct message) permission policy.
pub const DmPolicy = enum {
    /// Allow all DMs.
    /// Deny all DMs.
    /// Only allow DMs from senders in the allowlist.

/// Group/channel message permission policy.
pub const GroupPolicy = enum {
    /// Allow all group messages.
    /// Only respond when explicitly mentioned.
    /// Only allow messages from senders in the allowlist.

/// Per-channel permission policy configuration.
pub const ChannelPolicy = struct {

/// Check if a message is permitted under the given policy.
///
/// - `policy`: the channel permission policy to evaluate
/// - `sender_id`: the sender of the message
/// - `is_dm`: true if this is a direct message, false if group
/// - `is_mention`: true if the bot was mentioned (relevant for group mention_only)
pub fn checkPolicy(policy: ChannelPolicy, sender_id: []const u8, is_dm: bool, is_mention: bool) bool

/// Check if sender_id is in the given allowlist (case-insensitive, supports "*" wildcard).
fn inAllowlist(allowlist: []const []const u8, sender_id: []const u8) bool

/// Check if a user/sender is in an allowlist.
/// Supports "*" wildcard for allow-all.
pub fn isAllowed(allowed: []const []const u8, sender: []const u8) bool

/// Check if a user/sender is in an allowlist (exact match, no case folding).
pub fn isAllowedExact(allowed: []const []const u8, sender: []const u8) bool

/// Get current UNIX epoch seconds.
pub fn nowEpochSecs() u64

// ════════════════════════════════════════════════════════════════════════════
// Shared Utilities (re-exported from top-level modules)
// ════════════════════════════════════════════════════════════════════════════

/// HTTP POST via curl subprocess (safe on Zig 0.15, avoids std.http.Client segfaults).
pub const http_util = @import("../http_util.zig");

/// JSON string escaping (RFC 8259). appendJsonString adds enclosing quotes.
pub const json_util = @import("../json_util.zig");

/// Append a JSON-escaped string with enclosing quotes to any writer.
/// Writer-based variant of json_util.appendJsonString for fixed-buffer streams.
pub fn appendJsonStringW(writer: anytype, text: []const u8) !void

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "channel interface compiles" {
    // Compile-time check only — ensures the vtable types are coherent

test "splitMessage basic" {
    var it = splitMessage("hello world", 5);
    const a = it.next().?;
    const b = it.next().?;
    const c = it.next().?;

test "splitMessage exact boundary" {
    var it = splitMessage("abcde", 5);

test "splitMessage empty" {
    var it = splitMessage("", 100);

test "isAllowed wildcard" {
    const list = [_][]const u8{

test "isAllowed specific" {
    const list = [_][]const u8{

test "isAllowed empty denies all" {
    const list = [_][]const u8{

test "isAllowedExact case sensitive" {
    const list = [_][]const u8{

test "nowEpochSecs returns nonzero" {
    const t = nowEpochSecs();

// ════════════════════════════════════════════════════════════════════════════
// Additional Root Tests (ported from ZeroClaw Rust)
// ════════════════════════════════════════════════════════════════════════════

test "splitMessage single char max" {
    var it = splitMessage("abcdef", 1);

test "splitMessage utf8 multibyte respected" {
    // UTF-8: each CJK char is 3 bytes. With max_bytes=5, we can fit 1 char (3 bytes) but not 2 (6 bytes).
    var it = splitMessage("\xe4\xb8\x96\xe7\x95\x8c", 5); // "世界" (2 chars, 6 bytes)
    const chunk1 = it.next().?;
    const chunk2 = it.next().?;

test "splitMessage large max returns whole" {
    const msg = "hello world this is a test";
    var it = splitMessage(msg, 10000);

test "splitMessage two byte utf8" {
    // "aàb" - 'à' is 2 bytes (0xC3 0xA0), total 4 bytes
    const msg = "a\xc3\xa0b";
    var it = splitMessage(msg, 2);
    const chunk1 = it.next().?;
    // 'a' is 1 byte, 'à' is 2 bytes, so max=2 means: 'a' + partial 'à' won't fit, split at 1
    // Remaining should be valid UTF-8
    var total_len: usize = 0;

test "isAllowed multiple entries" {
    const list = [_][]const u8{

test "isAllowed case insensitive" {
    const list = [_][]const u8{

test "isAllowed empty sender" {
    const list = [_][]const u8{

test "isAllowedExact wildcard" {
    const list = [_][]const u8{

test "isAllowedExact empty list denies" {
    const list = [_][]const u8{

test "isAllowedExact exact match only" {
    const list = [_][]const u8{

test "isAllowedExact multiple entries" {
    const list = [_][]const u8{

test "isAllowed wildcard mixed with specific" {
    const list = [_][]const u8{

test "channel message struct fields" {

test "channel message reply_target defaults to null" {

test "channel message reply_target can be set" {

test "channel vtable struct has all fields" {
    // Compile-time check that all vtable fields exist
    const T = Channel.VTable;

test "splitMessage iterator is reusable after exhaust" {
    var it = splitMessage("ab", 1);
    // Calling again should still return null

test "nowEpochSecs returns recent timestamp" {
    const t = nowEpochSecs();
    // Should be after 2020-01-01
    // Should be before 2100-01-01

test "splitMessage emoji preserved" {
    // Single emoji is 4 bytes in UTF-8
    const msg = "\xf0\x9f\xa6\x80"; // 🦀
    var it = splitMessage(msg, 10);

// ════════════════════════════════════════════════════════════════════════════
// Per-Channel Permission Policy Tests
// ════════════════════════════════════════════════════════════════════════════

test "checkPolicy dm allow permits all" {
    const policy = ChannelPolicy{

test "checkPolicy dm deny blocks all" {
    const policy = ChannelPolicy{

test "checkPolicy dm allowlist permits listed senders" {
    const list = [_][]const u8{

test "checkPolicy dm allowlist case insensitive" {
    const list = [_][]const u8{

test "checkPolicy dm allowlist wildcard" {
    const list = [_][]const u8{

test "checkPolicy dm allowlist empty denies all" {
    const policy = ChannelPolicy{

test "checkPolicy group open permits all" {
    const policy = ChannelPolicy{

test "checkPolicy group mention_only requires mention" {
    const policy = ChannelPolicy{

test "checkPolicy group allowlist permits listed senders" {
    const list = [_][]const u8{

test "checkPolicy group allowlist ignores mention flag" {
    const list = [_][]const u8{

test "checkPolicy group allowlist empty denies all" {
    const policy = ChannelPolicy{

test "checkPolicy mixed dm and group on same policy" {
    const list = [_][]const u8{

test "checkPolicy default policy allows everything" {
    const policy = ChannelPolicy{

test "ChannelPolicy struct defaults" {
    const policy = ChannelPolicy{

test "DmPolicy enum values" {

test "GroupPolicy enum values" {

test "Channel sendRich falls back to send for plain text payload" {
    const Mock = struct {

    var mock = Mock{

test "Channel sendRich prefers structured vtable when available" {
    const Mock = struct {

    var mock = Mock{

test {
