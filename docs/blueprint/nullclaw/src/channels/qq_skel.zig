const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const bus = @import("../bus.zig");
const platform = @import("../platform.zig");
const websocket = @import("../websocket.zig");
const thread_stacks = @import("../thread_stacks.zig");
const Atomic = @import("../portable_atomic.zig").Atomic;

const log = std.log.scoped(.qq);

// ════════════════════════════════════════════════════════════════════════════
// Constants
// ════════════════════════════════════════════════════════════════════════════

pub const GATEWAY_URL = "wss://api.sgroup.qq.com/websocket";
pub const SANDBOX_GATEWAY_URL = "wss://sandbox.api.sgroup.qq.com/websocket";

pub const API_BASE = "https://api.sgroup.qq.com";
pub const SANDBOX_API_BASE = "https://sandbox.api.sgroup.qq.com";

/// QQ Gateway opcodes.

    pub fn fromInt(val: i64) ?Opcode

/// Default intents bitmask for QQ Bot API (zeroclaw parity):
///   bit 25: GROUP_AND_C2C_EVENT   — group @msg + C2C (private chat) events
///   bit 30: PUBLIC_GUILD_MESSAGES — public guild @msg events
/// See: https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html
pub const DEFAULT_INTENTS: u32 = (1 << 25) | (1 << 30);

// ════════════════════════════════════════════════════════════════════════════
// CQ Code Parsing (QQ message format)
// ════════════════════════════════════════════════════════════════════════════

/// Strip CQ codes from message text, returning clean text.
/// [CQ:at,qq=123] -> stripped
/// [CQ:face,id=178] -> stripped
/// [CQ:image,...] -> stripped
/// Regular text is preserved.
pub fn stripCqCodes(allocator: std.mem.Allocator, raw: []const u8) ![]u8

/// Extract the mentioned QQ number from a CQ-coded string.
/// Returns null if no [CQ:at,qq=...] tag is found.
pub fn extractMentionQQ(raw: []const u8) ?[]const u8

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool

fn isImageFilename(filename: []const u8) bool

fn isRemoteMediaUrl(url: []const u8) bool

const QQ_ATTACHMENT_CACHE_SUBDIR = "nullclaw_qq_media";
const QQ_ATTACHMENT_MAX_BYTES: usize = 20 * 1024 * 1024;

fn imageExtensionFromContentType(content_type: []const u8) []const u8

fn attachmentCacheDirPath(allocator: std.mem.Allocator) ![]u8

fn ensureAttachmentCacheDir(cache_dir: []const u8) !void


    var header_buf: [1][]const u8 = undefined;



    const cache_dir = try attachmentCacheDirPath(allocator);

    const ext = imageExtensionFromContentType(content_type);
    const ts: u64 = @intCast(@max(std.time.timestamp(), 0));
    const nonce = std.crypto.random.int(u64);

    var filename_buf: [96]u8 = undefined;
    const filename = std.fmt.bufPrint(&filename_buf, "qq_{

fn parseImageMarkerLine(line: []const u8) ?[]const u8

const ParsedOutgoingContent = struct {

/// Split outbound content into text and remote [IMAGE:URL] markers.
/// Non-remote markers stay in text; remote image URLs are extracted for media upload.
fn parseOutgoingContent(allocator: std.mem.Allocator, content: []const u8) !ParsedOutgoingContent

/// Extract image attachment markers as newline-joined "[IMAGE:<url>]".
/// Caller owns returned slice.
fn extractImageMarkers(allocator: std.mem.Allocator, payload: std.json.Value, auth_header_opt: ?[]const u8) ![]u8

// ════════════════════════════════════════════════════════════════════════════
// Message Deduplication
// ════════════════════════════════════════════════════════════════════════════

/// Runtime dedup capacity, aligned with zeroclaw (10k keys, evict half).
pub const DEDUP_CAPACITY: usize = 10_000;

pub const StringDedupSet = struct {

// ════════════════════════════════════════════════════════════════════════════
// Message Formatting
// ════════════════════════════════════════════════════════════════════════════

/// Build the IDENTIFY payload for QQ Gateway WebSocket.
/// Format: {"op":2,"d":{"token":"QQBot {access_token}","intents":N,"shard":[0,1]}}
pub fn buildIdentifyPayload(buf: []u8, access_token: []const u8, intents: u32) ![]const u8

/// Build a heartbeat payload.
/// Format: {"op":1,"d":N} where N is the last sequence number (or null).
pub fn buildHeartbeatPayload(buf: []u8, sequence: ?i64) ![]const u8

/// Build the REST API URL for sending a message to a channel.
pub fn buildSendUrl(buf: []u8, base: []const u8, channel_id: []const u8) ![]const u8

/// Build the REST API URL for sending a DM (direct message).
pub fn buildDmUrl(buf: []u8, base: []const u8, guild_id: []const u8) ![]const u8

/// Build the REST API URL for sending a group message.
/// Format: {base}/v2/groups/{group_openid}/messages
pub fn buildGroupSendUrl(buf: []u8, base: []const u8, group_openid: []const u8) ![]const u8

/// Build the REST API URL for sending a C2C (private) message.
/// Format: {base}/v2/users/{user_openid}/messages
pub fn buildC2cSendUrl(buf: []u8, base: []const u8, user_openid: []const u8) ![]const u8

/// Build the REST API URL for uploading a group media file descriptor.
/// Format: {base}/v2/groups/{group_openid}/files
pub fn buildGroupFilesUrl(buf: []u8, base: []const u8, group_openid: []const u8) ![]const u8

/// Build the REST API URL for uploading a C2C media file descriptor.
/// Format: {base}/v2/users/{user_openid}/files
pub fn buildC2cFilesUrl(buf: []u8, base: []const u8, user_openid: []const u8) ![]const u8

/// Build the REST API URL for resolving gateway endpoint.
/// Format: {base}/gateway
pub fn buildGatewayResolveUrl(buf: []u8, base: []const u8) ![]const u8

/// Build a message send body.
/// Format: {"content":"...", "msg_id":"..."}
    var body_list: std.ArrayListUnmanaged(u8) = .empty;



/// Build a media upload body for QQ /files endpoint.
/// Format: {"file_type":1,"url":"https://...","srv_send_msg":false}
pub fn buildMediaUploadBody(allocator: std.mem.Allocator, media_url: []const u8) ![]u8

/// Build a media send body after successful upload to /files.
/// Format: {"content":" ","msg_type":7,"media":{"file_info":"..."},"msg_id":"...","msg_seq":N}
    var body_list: std.ArrayListUnmanaged(u8) = .empty;



/// Build auth header value: "Authorization: QQBot {access_token}"
pub fn buildAuthHeader(buf: []u8, access_token: []const u8) ![]const u8

/// Fetch the current gateway URL for this bot/environment.
/// Caller owns returned memory.
pub fn fetchGatewayUrl(allocator: std.mem.Allocator, access_token: []const u8, sandbox: bool) ![]u8

/// Best-effort QQ API response check.
/// If payload includes a non-zero "code", treat it as an API failure.
fn ensureQqApiSuccess(allocator: std.mem.Allocator, resp_body: []const u8) !void

fn parseUploadedFileInfo(allocator: std.mem.Allocator, upload_response: []const u8) ![]u8

fn sanitizeUserOpenId(allocator: std.mem.Allocator, raw_id: []const u8) ![]u8

fn ensureHttpsMediaUrl(media_url: []const u8) ![]const u8

fn qqSeedFromSecret(secret: []const u8) ?[32]u8

    const seed = qqSeedFromSecret(app_secret) orelse return null;
    const key_pair = std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed) catch return null;
    const payload = try std.fmt.allocPrint(allocator, "{

/// Check if a group ID is allowed by the given config.
pub fn isGroupAllowed(config: config_types.QQConfig, group_id: []const u8) bool

/// Get the API base URL (sandbox or production).
pub fn apiBase(sandbox: bool) []const u8

/// URL for obtaining an access token via the QQ Bot OAuth2 flow.
pub const TOKEN_URL = "https://bots.qq.com/app/getAppAccessToken";

/// Refresh the access token this many seconds before it actually expires.
pub const TOKEN_REFRESH_MARGIN_SECS: i64 = 120;

/// Result of a successful token fetch.
pub const AccessTokenResult = struct {

/// Fetch a new access_token from the QQ Bot API.
/// Caller owns the returned `token` slice.
pub fn fetchAccessToken(allocator: std.mem.Allocator, app_id: []const u8, app_secret: []const u8) !AccessTokenResult

/// Get the Gateway URL (sandbox or production).
pub fn gatewayUrl(sandbox: bool) []const u8

/// Parse host from wss:// URL.
/// "wss://api.sgroup.qq.com/websocket" -> "api.sgroup.qq.com"
/// "wss://api.sgroup.qq.com/websocket?x=1" -> "api.sgroup.qq.com"
pub fn parseGatewayHost(wss_url: []const u8) []const u8

/// Parse port from wss:// URL.
/// Defaults to 443 when port is absent or invalid.
pub fn parseGatewayPort(wss_url: []const u8) u16

/// Parse path (and optional query) from wss:// URL.
/// Returns "/websocket" when no explicit path exists.
pub fn parseGatewayPath(wss_url: []const u8) []const u8

const invalid_socket: std.posix.socket_t = if (builtin.os.tag == .windows) std.os.windows.ws2_32.INVALID_SOCKET else -1;
// ════════════════════════════════════════════════════════════════════════════
// QQChannel
// ════════════════════════════════════════════════════════════════════════════

/// QQ Bot API channel.
///
/// Connects to the QQ Gateway via WebSocket for real-time messages.
/// Handles opcodes: HELLO (10), DISPATCH (0), HEARTBEAT_ACK (11), RECONNECT (7).
/// Sends replies via REST API POST to /channels/{id}/messages or /dms/{id}/messages.
/// Message deduplication via 10k-key hash set with half-eviction.
/// Auto-reconnect with 5s backoff.
pub const QQChannel = struct {
    // ── Access token state ──

// ════════════════════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════════════════════

/// Parse target string into (type, id, msg_id).
/// "channel:12345"              -> ("channel", "12345", null)
/// "dm:12345"                   -> ("dm", "12345", null)
/// "group:<openid>:<msg_id>"    -> ("group", "<openid>", "<msg_id>")
/// "c2c:<openid>:<msg_id>"      -> ("c2c", "<openid>", "<msg_id>")
/// "12345"                      -> ("c2c", "12345", null)
fn parseTarget(target: []const u8) struct

/// Get a string field from a JSON object value.
fn getJsonString(val: std.json.Value, key: []const u8) ?[]const u8

/// Get a string field from a JSON object value (alias for nested access).
fn getJsonStringFromObj(val: std.json.Value, key: []const u8) ?[]const u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "qq config defaults" {
    const config = config_types.QQConfig{

test "qq config custom values" {
    const list = [_][]const u8{

test "qq opcode fromInt" {

test "qq stripCqCodes plain text no tags" {
    const alloc = std.testing.allocator;
    const result = try stripCqCodes(alloc, "hello world");

test "qq stripCqCodes removes at tag" {
    const alloc = std.testing.allocator;
    const result = try stripCqCodes(alloc, "[CQ:at,qq=123456] hello");

test "qq stripCqCodes removes multiple tags" {
    const alloc = std.testing.allocator;
    const result = try stripCqCodes(alloc, "[CQ:at,qq=111] hi [CQ:image,file=pic.png]");

test "qq stripCqCodes empty string" {
    const alloc = std.testing.allocator;
    const result = try stripCqCodes(alloc, "");

test "qq stripCqCodes malformed tag preserved" {
    const alloc = std.testing.allocator;
    const result = try stripCqCodes(alloc, "broken [CQ:image,file=x");

test "qq stripCqCodes face tag stripped" {
    const alloc = std.testing.allocator;
    const result = try stripCqCodes(alloc, "hi [CQ:face,id=178] there");

test "qq extractMentionQQ finds mention" {
    const qq = extractMentionQQ("[CQ:at,qq=123456] hello");

test "qq extractMentionQQ returns null for no mention" {

test "qq extractMentionQQ malformed returns null" {

test "qq string dedup set basic behavior" {
    const alloc = std.testing.allocator;
    var dedup = StringDedupSet{

test "qq string dedup set evicts half at capacity" {
    const alloc = std.testing.allocator;
    var dedup = StringDedupSet{

test "qq buildIdentifyPayload" {
    var buf: [512]u8 = undefined;
    const payload = try buildIdentifyPayload(&buf, "my-access-token", DEFAULT_INTENTS);
    // Must NOT contain the old "Bot" format

test "qq buildHeartbeatPayload with sequence" {
    var buf: [64]u8 = undefined;
    const payload = try buildHeartbeatPayload(&buf, 42);

test "qq buildHeartbeatPayload null sequence" {
    var buf: [64]u8 = undefined;
    const payload = try buildHeartbeatPayload(&buf, null);

test "qq buildSendUrl" {
    var buf: [256]u8 = undefined;
    const url = try buildSendUrl(&buf, API_BASE, "chan123");

test "qq buildDmUrl" {
    var buf: [256]u8 = undefined;
    const url = try buildDmUrl(&buf, API_BASE, "guild456");

test "qq buildGatewayResolveUrl" {
    var buf: [256]u8 = undefined;
    const url = try buildGatewayResolveUrl(&buf, API_BASE);

test "qq buildSendBody" {
    const alloc = std.testing.allocator;
    const body = try buildSendBody(alloc, "hello world", null, null, null);

test "qq buildSendBody with msg_id" {
    const alloc = std.testing.allocator;
    const body = try buildSendBody(alloc, "reply text", "msg_123", null, null);

test "qq buildSendBody with msg_type" {
    const alloc = std.testing.allocator;
    const body = try buildSendBody(alloc, "reply text", "msg_123", 0, null);

test "qq buildSendBody with msg_seq" {
    const alloc = std.testing.allocator;
    const body = try buildSendBody(alloc, "reply text", "msg_123", 0, 2);

test "qq buildMediaUploadBody" {
    const alloc = std.testing.allocator;
    const body = try buildMediaUploadBody(alloc, "https://cdn.example.com/a.png");

test "qq buildMediaSendBody with passive fields" {
    const alloc = std.testing.allocator;
    const body = try buildMediaSendBody(alloc, "file-info-abc", "msg_123", 3);

test "qq parseUploadedFileInfo extracts file_info" {
    const alloc = std.testing.allocator;
    const file_info = try parseUploadedFileInfo(alloc, "{

test "qq ensureQqApiSuccess validates response payload" {
    const alloc = std.testing.allocator;

test "qq buildAuthHeader" {
    var buf: [256]u8 = undefined;
    const header = try buildAuthHeader(&buf, "my-access-token");

test "qq attachmentCacheDirPath uses system temp dir" {
    const alloc = std.testing.allocator;
    const tmp_dir = try platform.getTempDir(alloc);

    const cache_dir = try attachmentCacheDirPath(alloc);


test "qq isGroupAllowed policy allow" {
    const config = config_types.QQConfig{

test "qq isGroupAllowed policy allowlist" {
    const list = [_][]const u8{

test "qq isGroupAllowed empty allowlist denies all" {
    const config = config_types.QQConfig{

test "qq apiBase returns correct urls" {

test "qq gatewayUrl returns correct urls" {

test "qq parseGatewayHost from wss url" {
    const host = parseGatewayHost("wss://api.sgroup.qq.com/websocket");

test "qq parseGatewayHost strips explicit port" {
    const host = parseGatewayHost("wss://api.sgroup.qq.com:8443/websocket");

test "qq parseGatewayPort from wss url" {

test "qq parseGatewayPath from wss url with query" {
    const path = parseGatewayPath("wss://api.sgroup.qq.com/websocket?v=1");

test "qq parseGatewayPath defaults when missing explicit path" {
    const path = parseGatewayPath("wss://api.sgroup.qq.com");

test "qq fetchGatewayUrl returns static gateway in test mode" {
    const alloc = std.testing.allocator;
    const url = try fetchGatewayUrl(alloc, "test-access-token", false);

test "qq parseTarget channel prefix" {
    const msg_type, const id, const mid = parseTarget("channel:12345");

test "qq parseTarget dm prefix" {
    const msg_type, const id, const mid = parseTarget("dm:67890");

test "qq parseTarget no prefix defaults to c2c" {
    const msg_type, const id, const mid = parseTarget("12345");

test "qq parseTarget channel keeps extra colon in id" {
    const msg_type, const id, const mid = parseTarget("channel:abc:def");

test "qq parseImageMarkerLine extracts marker target" {
    const marker = parseImageMarkerLine(" [IMAGE:https://cdn.example.com/a.png] ").?;

test "qq parseOutgoingContent extracts remote image markers" {
    const alloc = std.testing.allocator;
    var parsed = try parseOutgoingContent(alloc, "hello\n[IMAGE:https://cdn.example.com/a.png]\n[IMAGE:http://cdn.example.com/b.jpg]\nbye");


test "qq parseOutgoingContent keeps non-remote marker as text" {
    const alloc = std.testing.allocator;
    var parsed = try parseOutgoingContent(alloc, "[IMAGE:/tmp/a.png]\nhello");


test "qq ensureHttpsMediaUrl rejects http" {
    const ok = try ensureHttpsMediaUrl("  https://cdn.example.com/a.png  ");

test "qq QQChannel init stores config" {
    const alloc = std.testing.allocator;

test "qq QQChannel vtable compiles" {
    const vtable_instance = QQChannel.vtable;

test "qq QQChannel channel interface" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent HELLO" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent READY" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent accepts large 64-bit sequence" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent ignores negative sequence" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent invalid sequence clears previous value" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent MESSAGE_CREATE" {
    const alloc = std.testing.allocator;
    var event_bus_inst = bus.Bus.init();

    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent MESSAGE_CREATE accepts msg_id fallback" {
    const alloc = std.testing.allocator;
    var event_bus_inst = bus.Bus.init();

    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent metadata escapes dynamic strings" {
    const alloc = std.testing.allocator;
    var event_bus_inst = bus.Bus.init();

    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent DIRECT_MESSAGE_CREATE" {
    const alloc = std.testing.allocator;
    var event_bus_inst = bus.Bus.init();

    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent deduplication" {
    const alloc = std.testing.allocator;
    var event_bus_inst = bus.Bus.init();

    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent group allowlist filters" {
    const alloc = std.testing.allocator;
    var event_bus_inst = bus.Bus.init();

    const list = [_][]const u8{

test "qq handleGatewayEvent drops sender when allow_from empty" {
    const alloc = std.testing.allocator;
    var event_bus_inst = bus.Bus.init();

    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent RECONNECT sets running false" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent INVALID_SESSION sets running false" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent HEARTBEAT_ACK is silent" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent HEARTBEAT requests immediate heartbeat" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{

test "qq handleGatewayEvent invalid JSON" {
    const alloc = std.testing.allocator;
    var ch = QQChannel.init(alloc, .{