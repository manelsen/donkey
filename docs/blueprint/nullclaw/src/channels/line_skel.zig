const std = @import("std");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");

const log = std.log.scoped(.line);

/// LINE Messaging API channel — webhook-based (push).
///
/// Receives events via LINE webhook endpoint, sends replies via
/// the Reply API (with replyToken) or Push API (direct to userId).
pub const LineChannel = struct {

// ════════════════════════════════════════════════════════════════════════════
// Parsed Event
// ════════════════════════════════════════════════════════════════════════════

pub const LineEvent = struct {

// ════════════════════════════════════════════════════════════════════════════
// Signature Verification
// ════════════════════════════════════════════════════════════════════════════

/// Verify a LINE webhook signature.
///
/// LINE signs webhook bodies with HMAC-SHA256(channel_secret, body),
/// then base64-encodes the result. The X-Line-Signature header contains
/// this base64-encoded HMAC.
pub fn verifyLineSignature(body: []const u8, signature: []const u8, channel_secret: []const u8) bool

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "line channel name" {

test "line config defaults" {

test "line config custom port" {

test "line health check returns true when running" {

test "line health check returns true with valid token" {

test "line health check returns false with no token and not running" {

test "line max message len constant" {

test "line api urls" {

// ── Signature Verification Tests ────────────────────────────────

test "line verifySignature with known values" {
    const body = "test body content";
    const secret = "my_channel_secret";

    // Compute expected signature
    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var mac: [HmacSha256.mac_length]u8 = undefined;

    var encoded_buf: [44]u8 = undefined;
    const expected_sig = std.base64.standard.Encoder.encode(&encoded_buf, &mac);


test "line verifySignature rejects wrong signature" {

test "line verifySignature rejects empty secret" {

test "line verifySignature rejects empty signature" {

test "line verifySignature rejects wrong secret" {
    const body = "test body";
    const correct_secret = "correct_secret";
    const wrong_secret = "wrong_secret";

    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var mac: [HmacSha256.mac_length]u8 = undefined;

    var encoded_buf: [44]u8 = undefined;
    const sig = std.base64.standard.Encoder.encode(&encoded_buf, &mac);


test "line verifySignature empty body with valid signature" {
    const body = "";
    const secret = "empty_body_secret";

    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var mac: [HmacSha256.mac_length]u8 = undefined;

    var encoded_buf: [44]u8 = undefined;
    const sig = std.base64.standard.Encoder.encode(&encoded_buf, &mac);


test "line verifySignature constant time comparison works" {
    const body = "timing test";
    const secret = "timing_secret";

    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var mac: [HmacSha256.mac_length]u8 = undefined;

    var encoded_buf: [44]u8 = undefined;
    const sig = std.base64.standard.Encoder.encode(&encoded_buf, &mac);

    // Valid signature passes

    // Altered last char fails
    var altered: [44]u8 = undefined;

// ── Event Parsing Tests ─────────────────────────────────────────

test "line parse text message event" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse image message event" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;

    // Image messages have no text

test "line parse audio message event" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse follow event" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse unfollow event" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse empty events array" {
    const allocator = std.testing.allocator;
    const events = try LineChannel.parseWebhookEvents(allocator, "{

test "line parse missing events field" {
    const allocator = std.testing.allocator;
    const events = try LineChannel.parseWebhookEvents(allocator, "{

test "line parse invalid json" {
    const allocator = std.testing.allocator;
    const events = try LineChannel.parseWebhookEvents(allocator, "not json at all");

test "line parse empty payload" {
    const allocator = std.testing.allocator;
    const events = try LineChannel.parseWebhookEvents(allocator, "{

test "line parse multiple events" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse group source" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse room source" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse message without source userId" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse event without source" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse sticker message (non-text)" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse mixed text and non-text events" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


    // Text message

    // Image message

    // Follow event

test "line vtable compiles" {
    // Verify all vtable function pointers are non-null

test "line channel interface" {
    const iface = ch.channel();

test "line channel start and stop" {
    const iface = ch.channel();

test "line event deinit frees all fields" {
    const allocator = std.testing.allocator;

test "line event deinit with null fields" {
    const allocator = std.testing.allocator;

test "line parse unicode text message" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parse postback event" {
    const allocator = std.testing.allocator;

    const events = try LineChannel.parseWebhookEvents(allocator, payload);
            var ev = e.*;


test "line parseAndFilterEvents blocks unlisted user" {
    const allocator = std.testing.allocator;


    const events = try ch.parseAndFilterEvents(payload);


test "line parseAndFilterEvents permits listed user" {
    const allocator = std.testing.allocator;


    const events = try ch.parseAndFilterEvents(payload);
            var ev = e.*;


test "line parseAndFilterEvents mixed allowlist keeps only allowed events" {
    const allocator = std.testing.allocator;


    const events = try ch.parseAndFilterEvents(payload);
            var ev = e.*;


test "line parseAndFilterEvents empty allow_from passes all" {
    const allocator = std.testing.allocator;


    const events = try ch.parseAndFilterEvents(payload);
            var ev = e.*;

