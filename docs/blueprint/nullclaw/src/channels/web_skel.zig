const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const bus_mod = @import("../bus.zig");
const ws_client = @import("../websocket.zig");
const config_types = @import("../config_types.zig");
const auth = @import("../auth.zig");
const pairing_mod = @import("../security/pairing.zig");
const secret_crypto = @import("../security/secrets.zig");
const websocket = @import("websocket");

const log = std.log.scoped(.web);

pub const WebChannel = struct {

/// Extract a query parameter value from a URL string.
/// Returns the value slice or null if not found.
fn extractQueryParam(url: []const u8, param_name: []const u8) ?[]const u8

fn extractPath(url: []const u8) []const u8

fn trimTrailingSlash(value: []const u8) []const u8

fn isOriginAllowed(allowed_origins: []const []const u8, origin: []const u8) bool

fn extractBearerToken(authorization_header: []const u8) ?[]const u8

const RelayEndpoint = struct {

fn parseRelayEndpoint(url: []const u8) !RelayEndpoint

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "WebChannel initFromConfig uses defaults" {
    const ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "WebChannel initFromConfig uses custom values" {

test "WebChannel parseMessageAuthMode marks unsupported mode as invalid" {

test "WebChannel wsStart fails fast for invalid message auth mode" {

test "WebChannel wsStart rejects token mode for relay transport" {

test "WebChannel initFromConfig maps relay transport settings" {

test "WebChannel initFromConfig falls back to default path for invalid value" {

test "WebChannel initFromConfig clamps max_connections to tracked limit" {

test "WebChannel initFromConfig normalizes zero handshake size to default" {

test "WebChannel vtable name returns web" {
    var ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "WebChannel generateToken produces 64 hex chars" {
    var ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "WebChannel validateToken accepts correct token" {
    var ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "WebChannel validateToken rejects wrong token" {
    var ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "WebChannel validateToken rejects wrong length" {
    var ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "WebChannel validateToken rejects before init" {
    const ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "WebChannel setBus stores bus reference" {
    var ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "WebChannel two instances have different tokens" {
    var ch1 = WebChannel.initFromConfig(std.testing.allocator, .{

test "extractQueryParam finds token" {

test "extractQueryParam finds param among multiple" {

test "extractQueryParam returns null for missing param" {

test "extractPath strips query" {

test "isOriginAllowed handles exact wildcard and slash normalization" {

    const wildcard = [_][]const u8{

test "extractBearerToken parses bearer auth header" {

test "parseRelayEndpoint parses host path and default port" {
    const ep = try parseRelayEndpoint("wss://relay.nullclaw.io/ws/agent");

test "parseRelayEndpoint parses explicit port" {
    const ep = try parseRelayEndpoint("wss://relay.nullclaw.io:9443/ws");

test "parseRelayEndpoint rejects non-wss URL" {

test "WebChannel setActiveToken rejects non url-safe tokens" {
    var ch = WebChannel.initFromConfig(std.testing.allocator, .{

test "ConnectionList add and remove" {
    const list = WebChannel.ConnectionList{

test "WsHandler clientMessage uses connection session id" {
    var bus = bus_mod.Bus.init();

    const access_token = try ch.issueUiAccessToken("ui-conn");

    const connection_sid = "conn-session";

    var event_buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = event_buf.writer(std.testing.allocator);


    const msg = bus.consumeInbound() orelse return error.TestUnexpectedResult;


test "WebChannel handleInboundEvent parses v1 envelope payload" {
    var bus = bus_mod.Bus.init();

    const access_token = try ch.issueUiAccessToken("ui-1");

    var event_buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = event_buf.writer(std.testing.allocator);

    const event = event_buf.items;

    const msg = bus.consumeInbound() orelse return error.TestUnexpectedResult;


test "WebChannel local token mode accepts user_message with auth_token" {

    var bus = bus_mod.Bus.init();

    const msg = bus.consumeInbound() orelse return error.TestUnexpectedResult;

test "WebChannel local token mode accepts token in access_token field for compatibility" {

    var bus = bus_mod.Bus.init();

    const msg = bus.consumeInbound() orelse return error.TestUnexpectedResult;

test "WebChannel local token mode rejects user_message without token" {

    var bus = bus_mod.Bus.init();


test "WebChannel local token mode rejects user_message with invalid token" {

    var bus = bus_mod.Bus.init();


test "WebChannel local token mode requires stable token source before start" {

test "WebChannel local token mode ignores pairing_request events" {

    var bus = bus_mod.Bus.init();


test "WebChannel relay UI access token verify and tamper detect" {

    const token = try ch.issueUiAccessToken("ui-test");

    var verified = ch.verifyUiAccessToken(token) orelse return error.TestUnexpectedResult;

    const tampered = try std.testing.allocator.dupe(u8, token);

test "WebChannel token mode does not initialize JWT signing state" {


test "WebChannel relay e2e payload helpers roundtrip" {
    const key = [_]u8{

test "WebChannel relay pairing request rotates one-time code and initializes e2e" {

    const code = ch.relay_pairing_guard.?.pairingCode() orelse return error.TestUnexpectedResult;
    const code_copy = try std.testing.allocator.dupe(u8, code);

    const client_kp = std.crypto.dh.X25519.KeyPair.generate();
    const client_pub_b64 = try ch.base64UrlEncodeAlloc(&client_kp.public_key);

    var event_buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = event_buf.writer(std.testing.allocator);

    const next_code = ch.relay_pairing_guard.?.pairingCode() orelse return error.TestUnexpectedResult;

test "WebChannel local pairing code is fixed to 123456 across rotations" {

    const first = ch.relay_pairing_guard.?.pairingCode() orelse return error.TestUnexpectedResult;

    const second = ch.relay_pairing_guard.?.pairingCode() orelse return error.TestUnexpectedResult;

test "WebChannel local pairing code never expires" {


test "WebChannel relay encrypted user_message is published to bus" {

    var bus = bus_mod.Bus.init();

    const key = [_]u8{

test "WebChannel relay user_message without access token is rejected" {

    var bus = bus_mod.Bus.init();

test {
