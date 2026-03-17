/// --probe-channel-health subcommand: validate channel credentials.
///
/// Usage: nullclaw --probe-channel-health --channel telegram --account default [--timeout-secs 10]
///
/// Returns JSON to stdout:
///   {"channel":"telegram","account":"default","live_ok":false,"reason":"missing_bot_token"}
const std = @import("std");
const config_mod = @import("config.zig");
const config_types = @import("config_types.zig");
const channel_catalog = @import("channel_catalog.zig");
const http_util = @import("http_util.zig");

const ProbeResult = struct {


const ParsedChannels = struct {

fn ok(channel: []const u8, account: []const u8) ProbeResult

fn fail(channel: []const u8, account: []const u8, reason: []const u8) ProbeResult

fn channelSupportsAccounts(channel_type: []const u8) bool

fn objectHasNonObjectValue(obj: std.json.ObjectMap) bool

fn firstObjectAccount(obj: std.json.ObjectMap) ?std.json.ObjectMap

fn pickAccountObject(obj: std.json.ObjectMap, requested: []const u8, channel_type: []const u8) ?std.json.ObjectMap

    const channel_value = channels_obj.get(channel_type) orelse return null;
    const channel_obj = channel_value.object;

    // Canonical config format: {"accounts": {"default": {...}}}

    // Multi-account channels in wizard payload format: {"default": {...}}

    // Single-account channels in canonical format: {"secret": "..."}

    // Single-account channels in wizard payload format: {"webhook": {"secret": "..."}}

fn trimWhitespace(s: []const u8) []const u8

fn nonEmptyString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8

fn optionalString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8

fn boolOrDefault(obj: std.json.ObjectMap, key: []const u8, fallback: bool) bool

fn u32OrDefault(obj: std.json.ObjectMap, key: []const u8, fallback: u32) u32

fn trimTrailingSlash(value: []const u8) []const u8

fn timeoutString(buf: []u8, timeout_secs: u64) []const u8

fn classifyProbeError(err: anyerror) []const u8

fn responseHasNonEmptyStringField(allocator: std.mem.Allocator, response: []const u8, key: []const u8) bool

fn extractJsonStringFieldOwned(allocator: std.mem.Allocator, response: []const u8, key: []const u8) ?[]u8

fn oneBotResponseLooksHealthy(allocator: std.mem.Allocator, response: []const u8) bool

fn timeoutPollMs(timeout_secs: u64) i32

fn tcpReachableWithTimeout(allocator: std.mem.Allocator, host: []const u8, port: u16, timeout_secs: u64) !void

fn allocOneBotApiBase(allocator: std.mem.Allocator, raw_url: []const u8) ![]u8

    const token = nonEmptyString(cfg, "bot_token") orelse return fail(channel, account, "missing_bot_token");
    const proxy = optionalString(cfg, "proxy");

    var url_buf: [1024]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const token = nonEmptyString(cfg, "token") orelse return fail(channel, account, "missing_token");

    var header_buf: [1024]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const token = nonEmptyString(cfg, "bot_token") orelse return fail(channel, account, "missing_bot_token");

    var header_buf: [1024]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const homeserver = nonEmptyString(cfg, "homeserver") orelse return fail(channel, account, "missing_homeserver");
    const access_token = nonEmptyString(cfg, "access_token") orelse return fail(channel, account, "missing_access_token");

    const base = trimTrailingSlash(homeserver);

    var header_buf: [2048]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const base_url = nonEmptyString(cfg, "base_url") orelse return fail(channel, account, "missing_base_url");
    const bot_token = nonEmptyString(cfg, "bot_token") orelse return fail(channel, account, "missing_bot_token");

    const base = trimTrailingSlash(base_url);

    var header_buf: [2048]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const http_url = nonEmptyString(cfg, "http_url") orelse return fail(channel, account, "missing_http_url");

    const base = trimTrailingSlash(http_url);


    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);

    const rest_probe = http_util.curlGet(allocator, url_rest, &.{

    const access_token = nonEmptyString(cfg, "access_token") orelse return fail(channel, account, "missing_access_token");

    var header_buf: [2048]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const access_token = nonEmptyString(cfg, "access_token") orelse return fail(channel, account, "missing_access_token");
    const phone_number_id = nonEmptyString(cfg, "phone_number_id") orelse return fail(channel, account, "missing_phone_number_id");

    var url_buf: [512]u8 = undefined;

    var header_buf: [2048]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const app_id = nonEmptyString(cfg, "app_id") orelse return fail(channel, account, "missing_app_id");
    const app_secret = nonEmptyString(cfg, "app_secret") orelse return fail(channel, account, "missing_app_secret");

    const use_feishu = boolOrDefault(cfg, "use_feishu", false);
    const base = if (use_feishu) "https://open.feishu.cn/open-apis" else "https://open.larksuite.com/open-apis";

    var url_buf: [512]u8 = undefined;

    var body_buf: [2048]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const client_id = nonEmptyString(cfg, "client_id") orelse return fail(channel, account, "missing_client_id");
    const client_secret = nonEmptyString(cfg, "client_secret") orelse return fail(channel, account, "missing_client_secret");

    var body_buf: [2048]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const app_id = nonEmptyString(cfg, "app_id") orelse return fail(channel, account, "missing_app_id");
    const app_secret = nonEmptyString(cfg, "app_secret") orelse return fail(channel, account, "missing_app_secret");

    var body_buf: [2048]u8 = undefined;

    var timeout_buf: [32]u8 = undefined;
    const timeout = timeoutString(&timeout_buf, timeout_secs);



    const sandbox = boolOrDefault(cfg, "sandbox", false);

    var header_buf: [2048]u8 = undefined;



    const endpoint = nonEmptyString(cfg, "url") orelse return fail(channel, account, "missing_url");



    var headers: [1][]const u8 = undefined;
    var headers_slice: []const []const u8 = &.{

    const host = nonEmptyString(cfg, "host") orelse return fail(channel, account, "missing_host");

    const port_raw = u32OrDefault(cfg, "port", 6697);
    const port: u16 = @intCast(port_raw);


    const smtp_host = nonEmptyString(cfg, "smtp_host") orelse return fail(channel, account, "missing_smtp_host");

    const smtp_port_raw = u32OrDefault(cfg, "smtp_port", 587);
    const smtp_port: u16 = @intCast(smtp_port_raw);


fn validateWebConfig(channel: []const u8, account: []const u8, cfg: std.json.ObjectMap) ProbeResult

fn validateConfigOnlyChannel(channel: []const u8, account: []const u8, cfg: std.json.ObjectMap) ProbeResult


    const meta = channel_catalog.findByKey(channel) orelse return fail(channel, account, "unknown_channel");

    const account_obj = resolveChannelAccountObject(channels_obj, channel, account) orelse return fail(channel, account, "account_not_found");



fn readChannelsObject(allocator: std.mem.Allocator) ReadConfigError!ParsedChannels

fn writeResult(result: ProbeResult) !void

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void

test "channelSupportsAccounts differentiates account models" {

test "classifyProbeError maps specific curl network errors" {

test "resolveChannelAccountObject handles canonical accounts wrapper" {
    const allocator = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{

test "resolveChannelAccountObject handles wizard account map" {
    const allocator = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{

test "resolveChannelAccountObject handles single-account wizard shape" {
    const allocator = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{

test "allocOneBotApiBase normalizes websocket schemes" {
    const allocator = std.testing.allocator;

    const ws_base = try allocOneBotApiBase(allocator, "ws://127.0.0.1:6700");

    const wss_base = try allocOneBotApiBase(allocator, "wss://onebot.example/ws");

test "oneBotResponseLooksHealthy validates retcode and status" {
    const allocator = std.testing.allocator;

    const ok_payload = "{
