const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const bus = @import("../bus.zig");
const secrets = @import("../security/secrets.zig");
const thread_stacks = @import("../thread_stacks.zig");

const log = std.log.scoped(.nostr);

/// DM protocol for protocol mirroring — reply using the same protocol the sender used.
pub const DmProtocol = enum {

/// Nostr channel — communicates via Nostr relays using NIP-17 (gift-wrapped DMs)
/// and NIP-04 (legacy encrypted DMs) with direct signing.
pub const NostrChannel = struct {
    /// Signing credential for --sec in all nak invocations.
    /// Either the decrypted private key (hex) or a pre-configured external bunker:// URI.
    /// Heap-allocated. Zeroed before free in vtableStop/deinit to reduce post-free exposure.
    /// Null before vtableStart is called.
    /// nak req --stream subprocess for listening to relay events.
    /// Event bus for publishing inbound messages to the agent.
    /// Reader thread that processes incoming events from the listener subprocess.
    /// Atomic flag to signal the reader thread to stop.
    /// Per-sender protocol mirroring: remembers which DM protocol each sender used.
    /// Accessed from both reader thread (writes) and outbound dispatcher (reads),
    /// so guard all map access with sender_protocols_mu.
    /// Recently-seen inner rumor IDs (kind:14 event id → arrival unix timestamp).
    /// Suppresses duplicate deliveries when the same rumor arrives via multiple relays.
    /// Discard events with created_at before this timestamp.
    /// Whether the channel has been started.

// ════════════════════════════════════════════════════════════════════════════
// Test Helpers
// ════════════════════════════════════════════════════════════════════════════

/// Helper for creating NostrChannel instances in tests with a minimal dummy config.
pub const TestHelper = struct {

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "NostrChannel vtable name returns nostr" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    const chan = ch.channel();

test "NostrChannel healthCheck returns false before start" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    // Also verify through the vtable
    const chan = ch.channel();

test "NostrChannel deinit on fresh instance does not leak" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    // If we reach here without the testing allocator complaining, no leaks occurred.

test "buildSendEventArgs constructs correct arguments" {
    var p_buf: [66]u8 = undefined;
    const p_tag = NostrChannel.formatPTag("deadbeef" ** 8, &p_buf);
    const args = NostrChannel.buildSendEventArgs("nak", "bunker://xyz", "hello", p_tag);

test "formatPTag builds correct tag" {
    var buf: [66]u8 = undefined;
    const tag = NostrChannel.formatPTag("abcd1234", &buf);

test "buildGiftWrapArgs constructs correct arguments with relays" {
    const relays: []const []const u8 = &.{

test "buildGiftWrapArgs with no relays leaves relay slots null" {
    const args = NostrChannel.buildGiftWrapArgs("nak", "sec", "pub", &.{

test "buildPublishArgs constructs correct arguments" {
    const args = NostrChannel.buildPublishArgs(config, "bunker://xyz");

test "buildPublishArgsWithRelays constructs correct arguments" {
    const relays: []const []const u8 = &.{

test "buildPublishOnlyArgs constructs arguments without signing key" {
    const relays: []const []const u8 = &.{

test "buildInboxLookupArgs constructs correct arguments" {
    const args = NostrChannel.buildInboxLookupArgs(config, "b" ** 64);

test "parseRelayTags extracts relay URLs from kind:10050 JSON" {
    const relays = try NostrChannel.parseRelayTags(std.testing.allocator, json);

test "parseRelayTags returns empty slice when no relay tags" {
    const relays = try NostrChannel.parseRelayTags(std.testing.allocator, json);

test "buildListenerArgs subscribes to kind:1059 and kind:4, on relays and dm_relays" {
    const args = NostrChannel.buildListenerArgs(config, "myseckey", "1700000000");

test "buildListenerArgs deduplicates relays present in both lists" {
    const args = NostrChannel.buildListenerArgs(config, "myseckey", "1700000000");
    // relay.damus.io and auth.nostr1.com appear exactly once each

test "buildUnwrapArgs constructs correct arguments" {
    const args = NostrChannel.buildUnwrapArgs("nak", "bunker://xyz");

test "parseUnwrappedRumor extracts sender and content" {
    const result = try NostrChannel.parseUnwrappedRumor(json);

test "parseUnwrappedRumor returns error on missing pubkey" {

test "parseUnwrappedRumor returns error on missing content" {

test "parseUnwrappedRumor returns error on missing created_at" {

test "isValidHexKey: accepts 64 lowercase hex chars" {

test "isValidHexKey: rejects wrong length" {

test "isValidHexKey: rejects uppercase hex" {

test "isValidHexKey: rejects npub prefix" {
    // npub1 is obviously not 64 hex chars, but also not hex

test "validateConfig: valid hex pubkey and enc2 key passes" {

test "validateConfig: npub owner_pubkey returns error" {

test "validateConfig: non-hex dm_allowed_pubkeys returns error" {

test "validateConfig: plaintext private_key returns error" {

test "validateConfig: nsec private_key returns error" {

test "validateConfig: bunker_uri skips private_key check" {

test "validateConfig: empty bot_pubkey returns error" {

test "isDmAllowed: owner always allowed" {

test "isDmAllowed: empty list denies non-owner" {

test "isDmAllowed: wildcard allows all" {

test "isDmAllowed: specific pubkey in list" {

test "sender_protocols tracks protocol per sender" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);

test "sender_protocols update does not leak on repeated sender" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);

test "NostrChannel registers with ChannelRegistry" {
    const allocator = std.testing.allocator;
    const dispatch = @import("dispatch.zig");

    var ch = TestHelper.initTestChannel(allocator);

    var reg = dispatch.ChannelRegistry.init(allocator);


test "NostrChannel health report via registry" {
    const allocator = std.testing.allocator;
    const dispatch = @import("dispatch.zig");

    var ch = TestHelper.initTestChannel(allocator);

    var reg = dispatch.ChannelRegistry.init(allocator);

    const report = reg.healthCheckAll();
    // Not started, so unhealthy

test "vtableSend returns NoSigningKey when not started" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    const chan = ch.channel();

test "setBus sets the event bus" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    var event_bus = bus.Bus.init();

test "buildSessionKey formats correctly" {
    var buf: [71]u8 = undefined;
    const key = NostrChannel.buildSessionKey("abcdef1234", &buf);

test "buildSessionKey truncates at 64 hex chars" {
    var buf: [71]u8 = undefined;
    const long_hex = "a" ** 80;
    const key = NostrChannel.buildSessionKey(long_hex, &buf);

test "processWrappedEvent publishes valid DM to bus" {
    const allocator = std.testing.allocator;

    var event_bus = bus.Bus.init();

    // processWrappedEvent calls runNakCommand which needs nak binary — skip in unit tests.
    // Instead, test the integration path components individually.
    // The buildSessionKey and parseUnwrappedRumor are already tested above.
    // The full integration requires a live nak binary and is tested manually.

test "reader thread fields initialize correctly" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);

test "vtableStop is safe on unstarted channel" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    const chan = ch.channel();
    // Should not panic or crash.

test "healthCheck returns false when reader exits naturally" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    // Simulate: channel was started, reader has since exited

test "healthCheck returns true when started and running" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);

test "buildInboxCreateArgs constructs kind:10050 create args" {
    var tag_bufs: [NostrChannel.MAX_RELAYS][NostrChannel.MAX_RELAY_TAG_LEN]u8 = undefined;
    const args = NostrChannel.buildInboxCreateArgs(config, "myhexkey", &tag_bufs);


test "extractEventKind returns correct kind" {
    const json = "{

test "extractEventKind returns null on missing kind" {

test "buildDecryptArgs constructs correct arguments" {
    const args = NostrChannel.buildDecryptArgs("nak", "myhexkey", "senderpubhex");

test "buildEncryptArgs constructs correct arguments" {
    const args = NostrChannel.buildEncryptArgs("nak", "myhexkey", "recipienthex");

test "buildNip04EventArgs constructs correct arguments" {
    var p_buf: [66]u8 = undefined;
    const p_tag = NostrChannel.formatPTag("deadbeef" ** 8, &p_buf);
    const args = NostrChannel.buildNip04EventArgs("nak", "myhexkey", "ciphertext?iv=abc", p_tag);

test "parseUnwrappedRumor extracts id field" {
    const result = try NostrChannel.parseUnwrappedRumor(json);

test "isSeenRumor returns false for unknown rumor id" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);

test "recordSeenRumor marks a rumor as seen" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);

test "recordSeenRumor evicts entries older than dedup window" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    const old_time: i64 = 1000;
    const now: i64 = old_time + NostrChannel.RUMOR_DEDUP_WINDOW_SECS + 1;

test "recordSeenRumor keeps entries within dedup window" {
    var ch = TestHelper.initTestChannel(std.testing.allocator);
    const base: i64 = 1000;
    const now: i64 = base + NostrChannel.RUMOR_DEDUP_WINDOW_SECS - 1;
