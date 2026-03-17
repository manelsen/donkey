const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const bus = @import("../bus.zig");
const http_util = @import("../http_util.zig");
const platform = @import("../platform.zig");
const websocket = @import("../websocket.zig");
const thread_stacks = @import("../thread_stacks.zig");

const log = std.log.scoped(.dingtalk);

const SocketFd = std.net.Stream.Handle;

const OPEN_CONNECTION_URL = "https://api.dingtalk.com/v1.0/gateway/connections/open";
const ACCESS_TOKEN_URL = "https://api.dingtalk.com/v1.0/oauth2/accessToken";
const DOWNLOAD_FILE_URL = "https://api.dingtalk.com/v1.0/robot/messageFiles/download";
const AI_INTERACTION_SEND_URL = "https://api.dingtalk.com/v1.0/aiInteraction/send";
const AI_INTERACTION_PREPARE_URL = "https://api.dingtalk.com/v1.0/aiInteraction/prepare";
const AI_INTERACTION_UPDATE_URL = "https://api.dingtalk.com/v1.0/aiInteraction/update";
const AI_INTERACTION_FINISH_URL = "https://api.dingtalk.com/v1.0/aiInteraction/finish";
const CALLBACK_TOPIC = "/v1.0/im/bot/messages/get";
const SYSTEM_TOPIC_DISCONNECT = "disconnect";
const USER_AGENT = "nullclaw-dingtalk/0.1.0";
const TOKEN_REFRESH_MARGIN_SECS: i64 = 300;
const RECONNECT_DELAY_NS: u64 = 5 * std.time.ns_per_s;
const ATTACHMENT_CACHE_SUBDIR = "nullclaw_dingtalk_media";
const ATTACHMENT_MAX_BYTES: usize = 20 * 1024 * 1024;
const REPLY_TARGET_CAPACITY: usize = 4096;
const BASIC_CARD_SCHEMA_CONTENT_TYPE = "basic_card_schema";
const AI_CARD_CONTENT_TYPE = "ai_card";
const BASIC_CARD_SCHEMA_TITLE = "nullclaw";
const BASIC_CARD_SCHEMA_LOGO = "@lALPDfJ6V_FPDmvNAfTNAfQ";
const STREAMING_COMPONENT_TAG = "streamingComponent";

const AccessTokenResult = struct {

const StreamConnection = struct {

const ParsedInboundMessage = struct {

const SessionReplyTarget = struct {

const ProactiveTargetKind = enum {

const ProactiveTarget = struct {

const StreamSession = struct {

const ReplyTargetCache = struct {

fn component_as_slice(component: std.Uri.Component) []const u8

fn status_code_is_success(code: u16) bool

fn json_string_from_obj(val: std.json.Value, key: []const u8) ?[]const u8

fn json_bool_from_obj(val: std.json.Value, key: []const u8) ?bool

fn json_i64_from_obj(val: std.json.Value, key: []const u8) ?i64

fn json_object_from_obj(val: std.json.Value, key: []const u8) ?std.json.Value

fn message_type_summary(msg_type: []const u8, file_name: ?[]const u8) []const u8

fn attachment_extension_from_type(msg_type: []const u8, file_name: ?[]const u8) []const u8

fn attachment_cache_dir_path(allocator: std.mem.Allocator) ![]u8

fn ensure_attachment_cache_dir(cache_dir: []const u8) !void

fn append_query_escaped(writer: anytype, value: []const u8) !void

    const uri = std.Uri.parse(endpoint) catch return error.DingTalkApiError;

    const host = uri.getHost(host_buf) catch return error.DingTalkApiError;
    const port = uri.port orelse 443;
    const raw_path = component_as_slice(uri.path);
    const raw_query = if (uri.query) |q| component_as_slice(q) else "";

    var fbs = std.io.fixedBufferStream(path_buf);
    const w = fbs.writer();


    var body: std.ArrayListUnmanaged(u8) = .empty;


fn parse_open_connection_response(allocator: std.mem.Allocator, resp_body: []const u8) !StreamConnection

    var body: std.ArrayListUnmanaged(u8) = .empty;


fn build_success_response_json(allocator: std.mem.Allocator, message: []const u8) ![]u8

fn build_response_null_json(allocator: std.mem.Allocator) ![]u8

fn should_ack_system_topic(topic: []const u8) bool

fn trim_prefix_ignore_case(text: []const u8, prefix: []const u8) ?[]const u8

fn build_basic_card_schema_content(allocator: std.mem.Allocator, text: []const u8) ![]u8

    const content = try build_basic_card_schema_content(allocator, text);

    var body: std.ArrayListUnmanaged(u8) = .empty;


fn build_ai_card_prepare_content(allocator: std.mem.Allocator, template_id: []const u8) ![]u8

    var body: std.ArrayListUnmanaged(u8) = .empty;


    const content = try build_ai_card_prepare_content(allocator, template_id);

    var body: std.ArrayListUnmanaged(u8) = .empty;


    var body: std.ArrayListUnmanaged(u8) = .empty;


fn build_ai_interaction_finish_body(allocator: std.mem.Allocator, conversation_token: []const u8) ![]u8

fn parse_prepare_conversation_token(allocator: std.mem.Allocator, resp_body: []const u8) ![]u8

fn validate_ai_interaction_response(allocator: std.mem.Allocator, resp_body: []const u8) !void

    if (comptime builtin.is_test) return null;

    const bytes = http_util.curlGetMaxBytes(allocator, source_url, &.{

/// DingTalk channel via Stream Mode WebSocket with session webhook replies.
pub const DingTalkChannel = struct {

        var body: std.ArrayListUnmanaged(u8) = .empty;


    fn sendViaSessionWebhook(self: *DingTalkChannel, target: SessionReplyTarget, text: []const u8) !void

    fn sendViaAiInteraction(self: *DingTalkChannel, proactive_target: ProactiveTarget, text: []const u8) !void

    fn prepareAiInteraction(self: *DingTalkChannel, proactive_target: ProactiveTarget) ![]u8

    fn updateAiInteraction(self: *DingTalkChannel, conversation_token: []const u8, content: []const u8) !void

    fn finishAiInteraction(self: *DingTalkChannel, conversation_token: []const u8) !void

    fn prepareAiInteractionForStreamingTarget(self: *DingTalkChannel, trimmed_target: []const u8) !?[]u8


        const trimmed_target = std.mem.trim(u8, target, " \t\r\n");



                var conversation_token_copy: []u8 = undefined;
                var full_text_copy: []u8 = undefined;


                    var pending_prepared_token: ?[]u8 = (try self.prepareAiInteractionForStreamingTarget(trimmed_target)) orelse return;


                        const owned_key = try self.allocator.dupe(u8, trimmed_target);
                                var removed = entry.value;

                        const inserted = self.stream_sessions.getPtr(trimmed_target).?;

                const removed = self.stream_sessions.fetchRemove(trimmed_target);

                    var session = entry.value;

                    const final_text = if (message.len > 0) message else session.buffer.items;


    fn parseCallbackPayload(self: *DingTalkChannel, payload: []const u8) !?ParsedInboundMessage

    fn publishInbound(self: *DingTalkChannel, msg: ParsedInboundMessage) !void

    fn handleEnvelope(self: *DingTalkChannel, ws: *websocket.WsClient, payload: []const u8) !bool

    fn runWebsocketOnce(self: *DingTalkChannel) !void

    fn websocketLoop(self: *DingTalkChannel) void

    /// Send a plain text reply through the session webhook URL or the AI interaction API.
    pub fn sendMessage(self: *DingTalkChannel, target: []const u8, text: []const u8, media: []const []const u8) !void

    fn vtableStart(ptr: *anyopaque) anyerror!void

    fn vtableStop(ptr: *anyopaque) void

    fn vtableSend(ptr: *anyopaque, target: []const u8, message: []const u8, media: []const []const u8) anyerror!void

        const self: *DingTalkChannel = @ptrCast(@alignCast(ptr));

    fn vtableName(ptr: *anyopaque) []const u8

    fn vtableHealthCheck(ptr: *anyopaque) bool


    pub fn channel(self: *DingTalkChannel) root.Channel

// ============================================================================
// Tests
// ============================================================================

test "build_open_connection_body subscribes to bot callback topic" {
    const body = try build_open_connection_body(std.testing.allocator, "cid", "secret");


test "parse_open_connection_response extracts endpoint and ticket" {


test "parse_endpoint_url appends encoded ticket" {
    var host_buf: [128]u8 = undefined;
    var path_buf: [256]u8 = undefined;


test "build_ack_json includes message id and escaped data" {


test "should_ack_system_topic skips disconnect" {

test "build_basic_card_schema_content trims outer whitespace and embeds text content" {
    const content = try build_basic_card_schema_content(std.testing.allocator, "  oi\\nDingTalk  ");


test "build_ai_interaction_send_body encodes conversation target" {


test "build_ai_interaction_prepare_body encodes union target and template" {


test "build_ai_card_streaming_content encodes finalize flag and streaming component" {


test "parse_prepare_conversation_token extracts nested token" {


test "parseProactiveTarget accepts account-qualified conversation and union targets" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "parseProactiveTarget rejects mismatched account prefix" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "parseProactiveTarget rejects direct conversation ids" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "parseCallbackPayload accepts sender_staff_id allowlist and rich text" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "parseCallbackPayload drops unauthorized sender" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "parseCallbackPayload falls back to message summary for file" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "parseCallbackPayload rolls back reply target cache on allocation failure" {

    var counting = std.testing.FailingAllocator.init(std.testing.allocator, .{

test "sendMessage rejects expired cached reply target" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendMessage falls back to ai interaction when cached reply target expired with conversation id" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendMessage rejects arbitrary webhook target" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendMessage accepts proactive union id target" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendMessage rejects media attachments" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendEventMessage chunk accumulates streaming session for reply target" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendEventMessage final clears streaming session" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendEventMessage without streaming config ignores chunks and safely finalizes" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendEventMessage final on nonexistent stream falls back safely" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "sendEventMessage direct reply target cannot open streaming session" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{

test "healthCheck requires running and connection" {
    var channel = DingTalkChannel.init(std.testing.allocator, "cid", "secret", &.{
