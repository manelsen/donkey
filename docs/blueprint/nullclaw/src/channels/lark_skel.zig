const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const bus = @import("../bus.zig");
const http_util = @import("../http_util.zig");
const websocket = @import("../websocket.zig");
const thread_stacks = @import("../thread_stacks.zig");

const log = std.log.scoped(.lark);

const SocketFd = std.net.Stream.Handle;
const AtomicU32 = std.atomic.Value(u32);
const DEFAULT_LARK_PING_INTERVAL_MS: u32 = 120 * std.time.ms_per_s;
const EVENT_CACHE_TTL_MS: i64 = 10_000;
const LARK_WS_METHOD_CONTROL: i32 = 0;
const LARK_WS_METHOD_DATA: i32 = 1;

const LarkWsConnectConfig = struct {

const LarkWsHeader = struct {

const LarkWsFrame = struct {

const LarkWsEventBuffer = struct {

const LarkWsPingLoopCtx = struct {

/// Lark/Feishu channel — receives events via WebSocket or HTTP callback, sends via Open API.
///
/// Supports two regional endpoints (configured via `use_feishu`):
/// - **Feishu** (default): CN endpoints at `open.feishu.cn`
/// - **Lark**: International endpoints at `open.larksuite.com`
pub const LarkChannel = struct {
    /// When true, use Feishu (CN) endpoints; when false, use Lark (international).
    /// Cached tenant access token (heap-allocated, owned by allocator).
    /// Epoch seconds when cached_token expires.
    /// Host root for callback endpoints (e.g. websocket config). Path is /callback/ws/endpoint, not under /open-apis.

pub const ParsedLarkMessage = struct {

// ════════════════════════════════════════════════════════════════════════════
// Helper functions
// ════════════════════════════════════════════════════════════════════════════

/// Flatten a Lark "post" rich-text message to plain text.
/// Post format: {"zh_cn": {"title": "...", "content": [[{"tag": "text", "text": "..."}]]}}
/// Returns null when content cannot be parsed or yields no usable text.
pub fn parsePostContent(allocator: std.mem.Allocator, post_json: []const u8) !?[]const u8

/// Remove `@_user_N` placeholder tokens injected by Feishu in group chats.
/// Patterns like "@_user_1", "@_user_2" are replaced with empty string.
pub fn stripAtPlaceholders(allocator: std.mem.Allocator, text: []const u8) ![]const u8

/// In group chats, only respond when the bot is explicitly @-mentioned.
/// For direct messages (p2p), always respond.
/// Checks: (1) mentions array is non-empty, or (2) text contains @bot_name.
pub fn shouldRespondInGroup(mentions_val: ?std.json.Value, text: []const u8, bot_name: []const u8) bool

fn queryParam(query: []const u8, key: []const u8) ?[]const u8

fn protoReadVarint(bytes: []const u8, index: *usize) !u64

fn protoReadLengthDelimited(bytes: []const u8, index: *usize) ![]const u8

fn protoSkipField(bytes: []const u8, index: *usize, wire_type: u64) !void

fn decodeLarkWsHeader(bytes: []const u8) !LarkWsHeader

fn decodeLarkWsFrame(allocator: std.mem.Allocator, bytes: []const u8) !LarkWsFrame

fn protoWriteVarint(writer: anytype, value: u64) !void

fn protoWriteTag(writer: anytype, field_number: u32, wire_type: u3) !void

fn protoWriteU64(writer: anytype, field_number: u32, value: u64) !void

fn protoWriteInt32(writer: anytype, field_number: u32, value: i32) !void

fn protoWriteBytes(writer: anytype, field_number: u32, value: []const u8) !void

fn protoWriteString(writer: anytype, field_number: u32, value: []const u8) !void

fn protoWriteHeader(writer: anytype, key: []const u8, value: []const u8) !void

fn larkWsHeaderValue(headers: []const LarkWsHeader, key: []const u8) ?[]const u8

fn isCardActionEventType(event_type: []const u8) bool

fn isCardActionPayload(payload: []const u8) bool

fn isCardActionAllowed(self: *const LarkChannel, event: std.json.Value) bool

    var out: std.ArrayListUnmanaged(u8) = .empty;
    const writer = out.writer(allocator);
        const encoded_len = std.base64.standard.Encoder.calcSize(raw.len);
        const encoded_buf = try allocator.alloc(u8, encoded_len);
        const encoded = std.base64.standard.Encoder.encode(encoded_buf, raw);

fn buildLarkWsPingFrame(buf: []u8, service_id: i32) ![]const u8

    var out: std.ArrayListUnmanaged(u8) = .empty;
    const writer = out.writer(allocator);

    var biz_rt_buf: [32]u8 = undefined;
    const biz_rt = std.fmt.bufPrint(&biz_rt_buf, "{

fn updatePingIntervalFromControlPayload(ping_interval_ms: *AtomicU32, payload: []const u8) void

    var stale_keys: std.ArrayListUnmanaged([]const u8) = .empty;

    var it = event_buffers.iterator();

            var value = entry.value;



    const sum = std.fmt.parseInt(usize, sum_raw, 10) catch return error.LarkApiError;
    const seq = std.fmt.parseInt(usize, seq_raw, 10) catch return error.LarkApiError;

    const trace_id = larkWsHeaderValue(frame.headers, "trace_id") orelse "";
    const gop = try event_buffers.getOrPut(allocator, message_id);
        const key_copy = try allocator.dupe(u8, message_id);

        const trace_id_copy = try allocator.dupe(u8, trace_id);

        const parts = try allocator.alloc(?[]u8, sum);


        const trace_id_copy = try allocator.dupe(u8, trace_id);

        const parts = try allocator.alloc(?[]u8, sum);




    var merged: std.ArrayListUnmanaged(u8) = .empty;
    const merged_payload = try merged.toOwnedSlice(allocator);

        var value = entry.value;


    var it = event_buffers.iterator();

fn larkWsPingLoop(ctx: *LarkWsPingLoopCtx) void

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "lark parse valid text message" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse group message marks is_group" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse unauthorized user" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse non-text skipped" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse wrong event type" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse empty text skipped" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

// ════════════════════════════════════════════════════════════════════════════
// Additional Lark Tests (ported from ZeroClaw Rust)
// ════════════════════════════════════════════════════════════════════════════

test "lark parse challenge produces no messages" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse non-object payload is ignored safely" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse invalid header shape is ignored safely" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse missing sender" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse missing event" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse invalid content json" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse unicode message" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse fallback sender to open_id when no chat_id" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark feishu base url constant" {

test "lark stores all fields" {
    const users = [_][]const u8{

// ════════════════════════════════════════════════════════════════════════════
// New feature tests
// ════════════════════════════════════════════════════════════════════════════

test "lark apiBase returns feishu URL when use_feishu is true" {
    var ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark apiBase returns larksuite URL when use_feishu is false" {
    var ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark buildWebsocketConfigUrl follows region" {
    var ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark buildWebsocketConfigBody uses official field names" {
    var buf: [256]u8 = undefined;
    const body = try LarkChannel.buildWebsocketConfigBody(&buf, "cli_app", "sec_123");

test "lark websocket pong and ack payload format" {
    var pong_buf: [128]u8 = undefined;
    const pong = try LarkChannel.buildWebsocketPong(&pong_buf, "123456");

    var ack_buf: [128]u8 = undefined;
    const ack = try LarkChannel.buildWebsocketAck(&ack_buf, "uuid-1");

test "lark initFromConfig stores account and receive mode" {
    const ch = LarkChannel.initFromConfig(std.testing.allocator, cfg);

test "lark healthCheck reflects receive mode state" {
    var ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark parsePostContent extracts text from single tag" {
    const allocator = std.testing.allocator;
    const result = try parsePostContent(allocator, post_json);

test "lark parsePostContent handles nested content array" {
    const allocator = std.testing.allocator;
    const result = try parsePostContent(allocator, post_json);
    // Should contain title, both lines, and link text

test "lark parsePostContent handles empty content" {
    const allocator = std.testing.allocator;
    const result = try parsePostContent(allocator, post_json);

test "lark stripAtPlaceholders removes @_user_1" {
    const allocator = std.testing.allocator;
    const result = try stripAtPlaceholders(allocator, "Hello @_user_1 how are you?");

test "lark stripAtPlaceholders removes multiple placeholders" {
    const allocator = std.testing.allocator;
    const result = try stripAtPlaceholders(allocator, "@_user_1 hello @_user_2 world");

test "lark stripAtPlaceholders no-op on clean text" {
    const allocator = std.testing.allocator;
    const result = try stripAtPlaceholders(allocator, "Hello world, no mentions here");

test "lark shouldRespondInGroup true for DM" {
    // For DMs (p2p), the caller skips the group check entirely.
    // But if called with a non-empty mentions array, should return true.
    const allocator = std.testing.allocator;
    const mentions_json = "[{

test "lark shouldRespondInGroup false when no mentions" {

test "lark shouldRespondInGroup true when bot name in text" {

test "lark token caching returns same token within expiry" {
    // We can only test the caching logic without a real API.
    // Verify that setting cached_token and a future expiry works.
    var ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark parse post message type via parseEventPayload" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark lark base url constant" {

test "lark parsePostContent at tag with user_name" {
    const allocator = std.testing.allocator;
    const result = try parsePostContent(allocator, post_json);

test "lark parsePostContent en_us locale fallback" {
    const allocator = std.testing.allocator;
    const result = try parsePostContent(allocator, post_json);

test "lark parsePostContent invalid json returns null" {
    const allocator = std.testing.allocator;
    const result = try parsePostContent(allocator, "not json at all");

test "lark stripAtPlaceholders preserves normal @ mentions" {
    const allocator = std.testing.allocator;
    const result = try stripAtPlaceholders(allocator, "Hello @john how are you?");
// ════════════════════════════════════════════════════════════════════════════
// WebSocket Tests
// ════════════════════════════════════════════════════════════════════════════

test "lark receive_mode defaults to websocket" {
    const ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark healthCheck webhook mode only checks running" {
    var ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark healthCheck websocket mode requires both running and connected" {
    var ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark extractWebsocketConnectUrl parses official response shape" {
    const allocator = std.testing.allocator;
    const url = try LarkChannel.extractWebsocketConnectUrl(allocator, resp);

test "lark extractWebsocketConnectConfig captures ping interval" {
    const allocator = std.testing.allocator;
    var cfg = try LarkChannel.extractWebsocketConnectConfig(allocator, resp);

test "lark parseWebsocketConnectUrl extracts host port and path" {
    var host_buf: [256]u8 = undefined;
    var path_buf: [512]u8 = undefined;

test "lark protobuf ping frame round-trips" {
    var buf: [256]u8 = undefined;
    const encoded = try buildLarkWsPingFrame(&buf, 9);
    var frame = try decodeLarkWsFrame(std.testing.allocator, encoded);

test "lark mergeLarkWsEventPayload merges chunked protobuf payload" {
    const allocator = std.testing.allocator;
    var event_buffers: std.StringHashMapUnmanaged(LarkWsEventBuffer) = .empty;



    const maybe_first = try mergeLarkWsEventPayload(allocator, &event_buffers, frame_0);

    const merged = (try mergeLarkWsEventPayload(allocator, &event_buffers, frame_1)).?;

test "lark protobuf event ack preserves frame metadata" {

    var decoded = try decodeLarkWsFrame(std.testing.allocator, encoded);


test "lark websocket ack payload base64 encodes callback response" {
    const allocator = std.testing.allocator;
    const payload = try buildLarkWsAckPayload(allocator, "{

test "lark protobuf event ack handles large callback payload" {
    const allocator = std.testing.allocator;
    const raw = try allocator.alloc(u8, 20_000);


    const ack_payload = try buildLarkWsAckPayload(allocator, callback_response);


    const encoded = try buildLarkWsEventAckFrame(allocator, src, 99, ack_payload);

    var decoded = try decodeLarkWsFrame(allocator, encoded);


test "lark buildWebsocketPong handles empty timestamp" {
    var pong_buf: [128]u8 = undefined;
    const pong = try LarkChannel.buildWebsocketPong(&pong_buf, "");

test "lark buildWebsocketAck handles empty uuid" {
    var ack_buf: [128]u8 = undefined;
    const ack = try LarkChannel.buildWebsocketAck(&ack_buf, "");

test "lark buildWebsocketPong handles unicode timestamp" {
    var pong_buf: [128]u8 = undefined;
    const pong = try LarkChannel.buildWebsocketPong(&pong_buf, "1234567890");

test "lark parseEventPayload handles websocket message format" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parseEventPayload handles websocket message with mentions" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark initFromConfig with websocket mode" {
    const ch = LarkChannel.initFromConfig(std.testing.allocator, cfg);

test "lark initFromConfig with webhook mode" {
    const ch = LarkChannel.initFromConfig(std.testing.allocator, cfg);

test "lark running and connected defaults" {
    const ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark invalidateToken clears cached token" {
    var ch = LarkChannel.init(std.testing.allocator, "id", "secret", "token", 9898, &.{

test "lark parseEventPayload websocket payload with post message" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse card action trigger emits choice message" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse card action trigger_v1 reads submit text" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse direct card action trigger keeps direct route" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse card action trigger reads form value" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{

test "lark parse card action trigger without open id requires wildcard allowlist" {
    const allocator = std.testing.allocator;
    const users = [_][]const u8{