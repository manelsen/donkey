//! Signal channel via signal-cli daemon HTTP/JSON-RPC.
//!
//! Connects to a running `signal-cli daemon --http <host:port>`.
//! Receives messages via SSE at `/api/v1/events` and sends via
//! JSON-RPC at `/api/v1/rpc`.
//!
//! Config example (in config.json):
//! ```json
//! {
//!   "channels": {
//!     "signal": {
//!       "accounts": {
//!         "default": {
//!           "http_url": "http://127.0.0.1:8080",
//!           "account": "+1234567890",
//!           "allow_from": ["+1111111111", "uuid:a1b2c3d4-..."],
//!           "group_allow_from": ["+1111111111"],
//!           "group_policy": "allowlist",
//!           "ignore_attachments": true,
//!           "ignore_stories": true
//!         }
//!       }
//!     }
//!   }
//! }
//! ```
//!
//! Environment variable override:
//!   SIGNAL_HTTP_URL, SIGNAL_ACCOUNT, SIGNAL_USE_REST_API
//!
//! Prerequisites:
//!   signal-cli must be running in daemon mode:
//!     signal-cli --account +1234567890 daemon --http 127.0.0.1:8080

const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const fs_compat = @import("../fs_compat.zig");
const sse_client = @import("../sse_client.zig");
const platform = @import("../platform.zig");
const thread_stacks = @import("../thread_stacks.zig");

const log = std.log.scoped(.signal);

// ════════════════════════════════════════════════════════════════════════════
// Constants
// ════════════════════════════════════════════════════════════════════════════

/// Prefix used to identify group targets in reply_target strings.
pub const GROUP_TARGET_PREFIX = "group:";

/// Interval for re-sending typing indicator (8 seconds).
const TYPING_INTERVAL_NS: u64 = 8 * std.time.ns_per_s;
const TYPING_SLEEP_STEP_NS: u64 = 100 * std.time.ns_per_ms; // 100ms sleep steps

/// Extract a stable group peer ID from reply_target.
/// For non-group targets returns the raw target or "unknown".
pub fn signalGroupPeerId(reply_target: ?[]const u8) []const u8

/// Health check endpoint for the signal-cli daemon.
const SIGNAL_HEALTH_ENDPOINT = "/api/v1/check";

/// JSON-RPC endpoint for sending messages.
const SIGNAL_RPC_ENDPOINT = "/api/v1/rpc";

/// SSE endpoint for receiving messages.
const SIGNAL_SSE_ENDPOINT = "/api/v1/events";

/// Signal reserves device id 1 for the primary device. Linked devices use
/// other ids; we use this to accept Note-to-Self only from the primary device
/// and fail closed for sync echoes originating from linked devices.
const SIGNAL_PRIMARY_DEVICE_ID: u64 = 1;

/// REST health endpoint (signal-cli-rest-api MODE=normal).
const SIGNAL_REST_HEALTH_ENDPOINT = "/v1/health";

/// REST endpoint for sending messages.
const SIGNAL_REST_SEND_ENDPOINT = "/v2/send";

/// REST receive endpoint prefix for polling messages.
const SIGNAL_REST_RECEIVE_ENDPOINT = "/v1/receive/";

/// Maximum message length for Signal messages (signal-cli has no hard limit,
/// but we chunk at 4096 to match typical messenger UX).
pub const MAX_MESSAGE_LEN: usize = 4096;

// ════════════════════════════════════════════════════════════════════════════
// Recipient Target
// ════════════════════════════════════════════════════════════════════════════

/// Classification of outbound message recipients.
    /// Direct message to a phone number or UUID.
    /// Group message by group ID.

// ════════════════════════════════════════════════════════════════════════════
// Signal Channel
// ════════════════════════════════════════════════════════════════════════════

/// Signal channel with dual transport support.
///
/// Default mode uses signal-cli daemon JSON-RPC + SSE.
/// When SIGNAL_USE_REST_API=1, uses signal-cli-rest-api REST endpoints.
pub const SignalChannel = struct {
    /// Base URL of the signal-cli daemon (e.g. "http://127.0.0.1:8080").
    /// Trailing slashes are stripped on init.
    /// Signal account identifier (E.164 phone, e.g. "+1234567890").
    /// Users allowed to interact. Empty = deny all (secure by default).
    /// Senders allowed in group chats when group_policy is allowlist.
    /// Empty means fallback to allow_from.
    /// Group policy: "open" | "allowlist" | "disabled".
    /// Skip messages that contain only attachments (no text).
    /// Skip story messages.
    /// Transport switch (env-gated): false = daemon JSON-RPC/SSE, true = REST.
    /// Persistent SSE connection for streaming message delivery.
    /// Initialized on first poll, maintained across polls for real-time delivery.
    /// Buffer for accumulating SSE data between reads.
    /// Backoff for reconnect attempts after SSE connect failures.
    /// Earliest wall-clock timestamp (seconds) for the next reconnect attempt.
    /// Typing indicator management (mirrors Discord implementation).

fn envFlagEnabled(allocator: std.mem.Allocator, name: []const u8) bool

fn jsonString(value: ?std.json.Value) ?[]const u8

fn jsonU64(value: ?std.json.Value) ?u64

fn normalizeEpochSeconds(timestamp: u64) u64

// ════════════════════════════════════════════════════════════════════════════
// Public Helpers
// ════════════════════════════════════════════════════════════════════════════

/// Strip the `uuid:` prefix from an allowlist entry if present.
///
/// This allows `uuid:<id>` and `<id>` to both match against a bare UUID sender.
pub fn normalizeAllowEntry(entry: []const u8) []const u8

/// Validate an E.164 phone number: starts with `+`, 2-15 digits after.
pub fn isE164(s: []const u8) bool

/// Check whether a string is a valid UUID (8-4-4-4-12 hex format).
///
/// Signal-cli uses UUIDs for privacy-enabled users who have opted out
/// of sharing their phone number.
pub fn isUuid(s: []const u8) bool

fn isHexDigit(c: u8) bool

/// Parse a recipient string into a RecipientTarget.
///
/// - "group:<id>" → Group
/// - E.164 phone or UUID → Direct
/// - Anything else → Group (conservative fallback, matches ironclaw)
pub fn parseRecipientTarget(recipient: []const u8) RecipientTarget

/// Determine the reply target from a data message.
///
/// - If the message is from a group, returns "group:<groupId>".
/// - Otherwise returns the sender's identifier (phone/UUID).
pub fn replyTarget(group_id: ?[]const u8, sender: []const u8) ReplyTargetResult

pub const ReplyTargetResult = struct {

/// Strip trailing slashes from a URL.
pub fn stripTrailingSlashes(url: []const u8) []const u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "channel name returns signal" {

test "creates with correct fields" {
    const users = [_][]const u8{

test "strips trailing slash" {

test "strips multiple trailing slashes" {

test "preserves url without trailing slash" {

test "wildcard allows anyone" {
    const users = [_][]const u8{

test "specific sender allowed" {
    const users = [_][]const u8{

test "unknown sender denied" {
    const users = [_][]const u8{

test "empty allowlist denies all" {

test "uuid prefix in allowlist" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "bare uuid in allowlist" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "multiple allowed users" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "uuid prefix normalization in allowlist" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "group sender allowlist filtering" {
    const senders = [_][]const u8{

test "group sender allowlist supports uuid-prefixed entries" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const senders = [_][]const u8{

test "group sender allowlist wildcard" {
    const senders = [_][]const u8{

test "group sender allowlist empty fallback path has no explicit entries" {

test "multiple allowed group senders" {
    const senders = [_][]const u8{

// ── Recipient Target Tests ──────────────────────────────────────────

test "parse recipient target e164 is direct" {
    const target = parseRecipientTarget("+1234567890");

test "parse recipient target prefixed group is group" {
    const target = parseRecipientTarget("group:abc123");

test "parse recipient target uuid is direct" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const target = parseRecipientTarget(uuid);

test "parse recipient target non e164 plus is group" {
    const target = parseRecipientTarget("+abc123");

// ── E.164 Validation Tests ──────────────────────────────────────────

test "is e164 valid numbers" {

test "is e164 invalid numbers" {

// ── UUID Validation Tests ───────────────────────────────────────────

test "is uuid valid" {

test "is uuid invalid" {

// ── Normalize Allow Entry Tests ─────────────────────────────────────

test "normalize allow entry strips uuid prefix" {

// ── Reply Target Tests ──────────────────────────────────────────────

test "reply target dm" {
    const result = replyTarget(null, "+1111111111");

test "reply target group" {
    const result = replyTarget("group123", "+1111111111");

// ── URL Builder Tests ───────────────────────────────────────────────

test "rpc url built correctly" {
    var buf: [1024]u8 = undefined;
    const url = try ch.rpcUrl(&buf);

test "sse url built correctly" {
    var buf: [1024]u8 = undefined;
    const url = try ch.sseUrl(&buf);

test "health url built correctly" {
    var buf: [1024]u8 = undefined;
    const url = try ch.healthUrl(&buf);

test "rest urls built correctly when enabled" {

    var send_buf: [1024]u8 = undefined;
    const send_url = try ch.sendUrl(&send_buf);

    var poll_buf: [1200]u8 = undefined;
    const poll_url = try ch.receivePollUrl(&poll_buf);

    var health_buf: [1024]u8 = undefined;
    const health_url = try ch.healthUrl(&health_buf);

test "build rest body direct uses v2 send schema keys" {


test "build rest body group uses recipients array" {


// ── JSON-RPC Body Tests ─────────────────────────────────────────────

test "build rpc body direct with message" {
    const body = try ch.buildRpcBody(std.testing.allocator, "send", .{

test "build rpc body direct without message" {
    const body = try ch.buildRpcBody(std.testing.allocator, "sendTyping", .{

test "signal startTyping and stopTyping are safe in tests" {

test "build rpc body group with message" {
    const body = try ch.buildRpcBody(std.testing.allocator, "send", .{

test "build rpc body group without message" {
    const body = try ch.buildRpcBody(std.testing.allocator, "sendTyping", .{

test "build rpc body uuid direct target" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const body = try ch.buildRpcBody(std.testing.allocator, "send", .{

test "build rpc body with attachments" {
    const attachments = &[_][]const u8{

test "build rpc body with single attachment" {
    const attachments = &[_][]const u8{

test "parse image markers extracts paths and strips markers from text" {


test "parse image markers preserves text when there are no markers" {
    const raw = "  keep leading and trailing whitespace \n";
    const parsed = try SignalChannel.parseImageMarkers(std.testing.allocator, raw);


test "parse image markers preserves text for malformed marker" {
    const raw = "prefix [IMAGE:] suffix";
    const parsed = try SignalChannel.parseImageMarkers(std.testing.allocator, raw);


test "prepare outgoing content merges media and deduplicates paths" {



test "prepare outgoing content keeps unresolved relative attachment path" {

    const marker_text = "[IMAGE:nullclaw_nonexistent_attachment_123456789.png]";
    const prepared = try ch.prepareOutgoingContent(marker_text, &.{

test "plan outgoing payloads sends attachment payloads without text" {
    const payloads = try SignalChannel.planOutgoingPayloads(std.testing.allocator, "hello", 2);


test "plan outgoing payloads splits text-only messages" {
    const long_text = try std.testing.allocator.alloc(u8, MAX_MESSAGE_LEN + 5);

    const payloads = try SignalChannel.planOutgoingPayloads(std.testing.allocator, long_text, 0);


// ── Process Envelope Tests ──────────────────────────────────────────

test "process envelope valid dm" {
    const users = [_][]const u8{

test "process envelope denied sender" {
    const users = [_][]const u8{

test "process envelope empty message" {
    const users = [_][]const u8{

test "process envelope no data message" {
    const users = [_][]const u8{

test "process envelope skips stories" {
    const users = [_][]const u8{

test "process envelope stories not skipped when disabled" {
    const users = [_][]const u8{

test "process envelope skips attachment only" {
    const users = [_][]const u8{

test "process envelope attachment with text not skipped" {
    const users = [_][]const u8{

test "process envelope attachment only not skipped when ignore disabled" {
    const users = [_][]const u8{

test "process envelope source name sets first name" {
    const users = [_][]const u8{

test "process envelope empty source name not set" {
    const users = [_][]const u8{

test "process envelope no source name not set" {
    const users = [_][]const u8{

test "process envelope dm accepted when group_allow_from is empty" {
    // group_allow_from applies to groups only; DMs are governed by allow_from.
    const users = [_][]const u8{

test "process envelope group with empty group_allow_from falls back to allow_from" {
    // Empty group_allow_from = fall back to allow_from for sender check.
    const users = [_][]const u8{

test "process envelope group denied when sender not in group_allow_from" {
    // group_allow_from has specific senders; this sender is not in the list.
    const users = [_][]const u8{

test "process envelope group accepted when sender in group_allow_from" {
    const users = [_][]const u8{

test "process envelope group accepts uuid allowlist when source_number is present" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "process envelope group sender not in group_allow_from" {
    const users = [_][]const u8{

test "process envelope group blocked when group_policy disabled" {
    const users = [_][]const u8{

test "process envelope group allowed when group_policy open" {
    const users = [_][]const u8{

test "process envelope uuid sender dm" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "process envelope uuid sender in group" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "process envelope dm has no is_group flag" {
    const users = [_][]const u8{

test "process envelope group sets is_group" {
    const users = [_][]const u8{

test "process envelope uses data message timestamp" {
    const users = [_][]const u8{

test "process envelope falls back to envelope timestamp" {
    const users = [_][]const u8{

test "process envelope normalizes millisecond timestamps to seconds" {
    const users = [_][]const u8{

test "process envelope generates timestamp when missing" {
    const users = [_][]const u8{

test "process envelope sender prefers source number" {
    const users = [_][]const u8{

test "process envelope sender falls back to source" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "process envelope sender none when both missing" {
    const users = [_][]const u8{

test "process envelope ignores self messages" {
    const users = [_][]const u8{

test "parseSSEEnvelope returns owned message content" {
    const users = [_][]const u8{

test "parseSSEEnvelope accepts sourceUuid field" {
    const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const users = [_][]const u8{

test "parseSSEEnvelope ignores syncMessage payloads" {
    const users = [_][]const u8{

test "parseSSEEnvelope accepts editMessage dataMessage fallback" {
    const users = [_][]const u8{

test "nextEventBoundary handles lf and crlf delimiters" {
    const lf_data = "data: one\n\nrest";
    const lf_boundary = SignalChannel.nextEventBoundary(lf_data, 0).?;

    const crlf_data = "data: two\r\n\r\nrest";
    const crlf_boundary = SignalChannel.nextEventBoundary(crlf_data, 0).?;

test "parseSSEEnvelope accepts multiline SSE data payload" {
    const users = [_][]const u8{

// ── Vtable Tests ────────────────────────────────────────────────────

test "vtable struct has all fields" {
    const T = root.Channel.VTable;

test "vtable compiles and wires correctly" {
    const iface = ch.channel();

test "stripTrailingSlashes no slash" {

test "stripTrailingSlashes one slash" {

test "stripTrailingSlashes many slashes" {

test "stripTrailingSlashes empty string" {

test "stripTrailingSlashes only slashes" {

test "parseSSEEnvelope processes Note to Self sync message" {
    const users = [_][]const u8{

test "parseSSEEnvelope ignores sync outbound to other recipient" {
    const users = [_][]const u8{

test "parseSSEEnvelope ignores Note to Self from non-allowed sender" {
    const users = [_][]const u8{

test "parseSSEEnvelope ignores sync with empty sentMessage" {
    const users = [_][]const u8{

test "parseSSEEnvelope ignores Note to Self sync from linked device" {
    const users = [_][]const u8{
