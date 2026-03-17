//! Generic RFC 6455 WebSocket client.
//! Used by Discord, Lark, DingTalk, QQ gateway channels and OneBot.
//! Supports both `wss://` and `ws://` transports.

const std = @import("std");

const log = std.log.scoped(.websocket);

/// RFC 6455 handshake magic string.
pub const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/// WebSocket opcodes (RFC 6455 §5.2).

/// A parsed WebSocket frame.
/// `payload.len > 0` → heap-allocated; free with allocator.free(frame.payload).
/// `payload.len == 0` → empty static slice; do NOT free.
pub const Frame = struct {

/// Heap-allocated TLS state.
/// Must be heap-allocated so internal pointers remain stable after init.
pub const TlsState = struct {

/// WebSocket client over TLS.
/// `write_mu` serializes concurrent writes (heartbeat + gateway threads).
pub const WsClient = struct {
    /// Connect to wss://host:port/path.
    /// `extra_headers`: additional HTTP request headers (without trailing CRLF).

// ════════════════════════════════════════════════════════════════════════════
// Pure utility functions (testable without network)
// ════════════════════════════════════════════════════════════════════════════

/// Build a masked WebSocket frame into `buf`. Returns bytes written.
/// mask_key: 4-byte masking key to use (caller controls for deterministic tests).
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();

    // Byte 0: FIN=1, RSV=0, opcode

    // Byte 1: MASK=1 + payload length
    const plen = payload.len;
        const p64: u64 = plen;

    // Masking key

    // Masked payload


/// Parse a WebSocket frame header from raw bytes (server→client, unmasked).
/// Returns header metadata and how many bytes the header consumed.
pub const ParsedHeader = struct {

pub fn parseFrameHeader(bytes: []const u8) !ParsedHeader

/// Apply WebSocket XOR masking in-place.
pub fn applyMask(payload: []u8, mask_key: [4]u8) void

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "ws accept key known value" {
    // Known test vector from RFC 6455 Section 1.3
    // Client key: "dGhlIHNhbXBsZSBub25jZQ=="
    // Expected:   "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    const key = "dGhlIHNhbXBsZSBub25jZQ==";
    const accept = WsClient.computeAcceptKey(key);

test "ws connectPlain compiles with nullable tls transport" {

test "ws accept key length" {
    var key: [24]u8 = undefined;
    const accept = WsClient.computeAcceptKey(&key);

test "ws handshake key is 24 chars base64" {
    var key_raw: [16]u8 = undefined;
    var key_b64: [24]u8 = undefined;
    // 16 bytes → 24 base64 chars (no padding needed since 16 is divisible by 3? No, 16/3=5r1 → 24 with padding)
    // Actually 16 bytes = 128 bits → ceil(128/6) = 22 chars + 2 padding = 24. Correct.
    // Verify all chars are valid base64

test "ws opcode enum values" {

test "ws buildFrame text empty payload" {
    var buf: [16]u8 = undefined;
    const mask: [4]u8 = .{

test "ws buildFrame text short payload" {
    var buf: [32]u8 = undefined;
    const mask: [4]u8 = .{

test "ws buildFrame ping opcode" {
    var buf: [16]u8 = undefined;
    const mask: [4]u8 = .{

test "ws buildFrame close opcode" {
    var buf: [16]u8 = undefined;
    const mask: [4]u8 = .{

test "ws buildFrame pong opcode" {
    var buf: [16]u8 = undefined;
    const mask: [4]u8 = .{

test "ws buildFrame 126-byte payload" {
    // Payload of exactly 126 bytes requires 2-byte extended length
    var buf: [256]u8 = undefined;
    const mask: [4]u8 = .{

test "ws buildFrame 65535-byte payload uses 2-byte extended length" {
    // Verify header bytes for 65535-byte payload
    var buf: [65535 + 14]u8 = undefined;
    const mask: [4]u8 = .{

test "ws buildFrame 65536-byte payload uses 8-byte extended length" {
    // 65536 bytes requires 8-byte extended length
    const payload_len = 65536;
    var buf: [payload_len + 14]u8 = undefined;
    const mask: [4]u8 = .{

test "ws parseFrameHeader short text frame unmasked" {
    // Server sends unmasked text frame: FIN=1, op=1, len=5
    const bytes = [_]u8{

test "ws parseFrameHeader 126 extended length" {
    const bytes = [_]u8{

test "ws parseFrameHeader 127 extended length" {
    // 8-byte extended length = 70000
    const bytes = [_]u8{

test "ws parseFrameHeader continuation frame" {
    const bytes = [_]u8{

test "ws parseFrameHeader masked frame header_bytes includes mask" {
    // Masked frame: MASK bit set → header_bytes includes 4 mask bytes
    const bytes = [_]u8{

test "ws parseFrameHeader insufficient data returns error" {
    const bytes = [_]u8{

test "ws applyMask XOR correctness" {
    var payload = [_]u8{

test "ws applyMask empty payload is no-op" {
    var payload: [0]u8 = .{

test "ws applyMask single byte" {
    var payload = [_]u8{

test "ws buildFrame masking is correct" {
    // Build frame and verify masking
    const payload = "Test";
    const mask = [4]u8{

test "ws WS_MAGIC constant" {

test "ws computeAcceptKey is deterministic" {
    const key = "dGhlIHNhbXBsZSBub25jZQ==";
    const a1 = WsClient.computeAcceptKey(key);
    const a2 = WsClient.computeAcceptKey(key);

test "ws parseFrameHeader close frame" {
    const bytes = [_]u8{

test "ws parseFrameHeader ping frame" {
    const bytes = [_]u8{

test "ws buildFrame zero-len payload close" {
    var buf: [16]u8 = undefined;
    const mask: [4]u8 = .{

// Regression: v2026.3.12 applied a blanket `n == 0 → ConnectionClosed` check
// to both TLS and plain socket paths. TLS readVec may return 0 while it
// refills its internal buffer or processes post-handshake records, so only
// plain sockets should treat a zero-byte read as EOF.

fn fake_tls_test_stream(_: *std.Io.Reader, _: *std.Io.Writer, _: std.Io.Limit) std.Io.Reader.StreamError!usize

fn fake_tls_read_vec_zero_then_byte(reader: *std.Io.Reader, data: [][]u8) std.Io.Reader.Error!usize

test "ws readExact TLS tolerates transient zero readVec return" {
    var tls_reader_storage = [_]u8{

test "ws readExact plain returns ConnectionClosed on immediate EOF" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;
    const fds = try std.posix.pipe();


    var buf: [1]u8 = undefined;

test "ws readExact plain reads data then ConnectionClosed on EOF" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;
    const fds = try std.posix.pipe();



    // First read succeeds
    var buf: [2]u8 = undefined;

    // Next read hits EOF
    var buf2: [1]u8 = undefined;
