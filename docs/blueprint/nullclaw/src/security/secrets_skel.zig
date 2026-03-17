const std = @import("std");
const ChaCha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const log = std.log.scoped(.secrets);

/// Length of the random encryption key in bytes (256-bit).
pub const KEY_LEN: usize = 32;

/// ChaCha20-Poly1305 nonce length in bytes.
pub const NONCE_LEN: usize = 12;

/// Tag length
pub const TAG_LEN: usize = ChaCha20Poly1305.tag_length;

/// Encrypt data using ChaCha20-Poly1305 (Zig stdlib).
pub fn encrypt(key: [32]u8, nonce: [12]u8, plaintext: []const u8, buf: []u8) ![]const u8

/// Decrypt data using ChaCha20-Poly1305.
pub fn decrypt(key: [32]u8, nonce: [12]u8, ciphertext: []const u8, buf: []u8) ![]const u8

/// HMAC-SHA256 for webhook signature verification.
pub fn hmacSha256(key: []const u8, message: []const u8) [HmacSha256.mac_length]u8

/// Hex-encode bytes to a lowercase hex string.
pub fn hexEncode(data: []const u8, buf: []u8) []const u8

/// Hex-decode a hex string to bytes.
pub fn hexDecode(hex: []const u8, buf: []u8) ![]const u8

fn hexVal(c: u8) ?u4

/// Manages encrypted storage of secrets (API keys, tokens, etc.)
/// Secrets are encrypted using ChaCha20-Poly1305 AEAD with a random key
/// stored on disk with restrictive file permissions.
pub const SecretStore = struct {
    /// Path to the key file
    /// Whether encryption is enabled
    /// Create a new secret store rooted at the given directory.

// ── Tests ──────────────────────────────────────────────────────────────

test "encrypt then decrypt roundtrip" {
    const key = [_]u8{

test "hmac produces correct length" {
    const result = hmacSha256("secret", "message");

test "hex encode decode roundtrip" {
    const data = [_]u8{

test "hex decode odd length fails" {
    var buf: [4]u8 = undefined;

test "hex decode invalid chars fails" {
    var buf: [4]u8 = undefined;

test "secret store encrypt decrypt roundtrip" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store encrypt empty returns empty" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store decrypt plaintext passthrough" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store disabled returns plaintext" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store is encrypted detects prefix" {

test "secret store encrypting same value produces different ciphertext" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store different dirs cannot decrypt each other" {
    var tmp1 = std.testing.tmpDir(.{

test "secret store same dir interop" {
    var tmp_dir = std.testing.tmpDir(.{

// ── Additional encryption tests ──────────────────────────────────

test "secret store unicode roundtrip" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store key file created on first encrypt" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store tampered ciphertext detected" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store truncated ciphertext returns error" {
    var tmp_dir = std.testing.tmpDir(.{

test "secret store corrupt hex returns error" {
    var tmp_dir = std.testing.tmpDir(.{

test "encrypt with different nonce produces different output" {
    const key = [_]u8{

test "decrypt with wrong key fails" {
    const key1 = [_]u8{

test "encrypt buffer too small fails" {
    const key = [_]u8{

test "decrypt ciphertext too short fails" {
    const key = [_]u8{

test "hmac same input same output" {
    const r1 = hmacSha256("key", "message");
    const r2 = hmacSha256("key", "message");

test "hmac different keys different output" {
    const r1 = hmacSha256("key1", "message");
    const r2 = hmacSha256("key2", "message");

test "hmac different messages different output" {
    const r1 = hmacSha256("key", "message1");
    const r2 = hmacSha256("key", "message2");

test "hex encode empty" {
    var buf: [4]u8 = undefined;
    const result = hexEncode(&[_]u8{

test "hex decode empty" {
    var buf: [4]u8 = undefined;
    const result = try hexDecode("", &buf);

test "hex encode all bytes" {
    const data = [_]u8{

test "hex decode uppercase" {
    var buf: [2]u8 = undefined;
    const result = try hexDecode("AABB", &buf);

test "hex decode mixed case" {
    var buf: [2]u8 = undefined;
    const result = try hexDecode("aAbB", &buf);

test "secret store is encrypted short strings" {

test "secret store encrypt decrypt multiple values same store" {
    var tmp_dir = std.testing.tmpDir(.{
