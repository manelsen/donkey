const std = @import("std");
const crypto = @import("../security/secrets.zig");

/// Maximum failed pairing attempts before lockout.
const MAX_PAIR_ATTEMPTS: u32 = 5;
/// Lockout duration after too many failed pairing attempts (5 minutes).
const PAIR_LOCKOUT_NS: i128 = 300 * std.time.ns_per_s;

/// Manages pairing state for the gateway.
///
/// Bearer tokens are stored as SHA-256 hashes to prevent plaintext exposure
/// in config files. When a new token is generated, the plaintext is returned
/// to the client once, and only the hash is retained.
pub const PairingGuard = struct {
    /// Whether pairing is required at all.
    /// One-time pairing code (generated on startup, consumed on first pair).
    /// Set of SHA-256 hashed bearer tokens (hex strings).
    /// Brute-force protection

/// Generate a 6-digit numeric pairing code using cryptographic randomness.
fn generateCode() [6]u8

/// Generate a bearer token with 256-bit entropy.
fn generateToken() [67]u8

/// SHA-256 hash a bearer token. Returns lowercase hex in the provided buffer.
fn hashToken(token: []const u8, buf: *[64]u8) []const u8

/// SHA-256 hash a token, returning an allocated hex string
fn hashTokenAlloc(allocator: std.mem.Allocator, token: []const u8) ![]u8

/// Check if a stored value looks like a SHA-256 hash (64 hex chars)
fn isTokenHash(value: []const u8) bool

/// Constant-time string comparison to prevent timing attacks.
pub fn constantTimeEq(a: []const u8, b: []const u8) bool

/// Check if a host string represents a non-localhost bind address.
pub fn isPublicBind(host: []const u8) bool

// ── Tests ──────────────────────────────────────────────────────────────

test "new guard generates code when no tokens" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "new guard no code when tokens exist" {
    const tokens = [_][]const u8{

test "new guard no code when pairing disabled" {
    var guard = try PairingGuard.init(std.testing.allocator, false, &.{

test "is authenticated when pairing disabled" {
    var guard = try PairingGuard.init(std.testing.allocator, false, &.{

test "is authenticated with valid token" {
    const tokens = [_][]const u8{

test "is authenticated with prehashed token" {
    var hash_buf: [64]u8 = undefined;
    const hashed = hashToken("zc_valid", &hash_buf);
    var hashed_copy: [64]u8 = undefined;
    const tokens = [_][]const u8{

test "is authenticated with invalid token" {
    const tokens = [_][]const u8{

test "tokens stored as hashes" {
    const tokens = [_][]const u8{

test "constant time eq same" {

test "constant time eq different" {

test "generate code is 6 digits" {
    const code = generateCode();

test "generate code is not deterministic" {
    // Two codes should differ with overwhelming probability
    var found_different = false;
        const c1 = generateCode();
        const c2 = generateCode();

test "generate token has prefix" {
    const token = generateToken();

test "hash token produces 64 hex chars" {
    var buf: [64]u8 = undefined;
    const hash = hashToken("zc_test_token", &buf);

test "hash token is deterministic" {
    var buf1: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    const h1 = hashToken("zc_abc", &buf1);
    const h2 = hashToken("zc_abc", &buf2);

test "hash token differs for different inputs" {
    var buf1: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    const h1 = hashToken("zc_a", &buf1);
    const h2 = hashToken("zc_b", &buf2);

test "is token hash detects hash vs plaintext" {
    var buf: [64]u8 = undefined;
    const hash = hashToken("zc_test", &buf);
    var hash_arr: [64]u8 = undefined;

test "localhost variants not public" {

test "zero zero is public" {

test "real ip is public" {

// ── Additional pairing tests ────────────────────────────────────

test "brute force lockout after max attempts" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "failed attempts increment" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "lockout time set after max attempts" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "multiple tokens can be added" {
    const tokens = [_][]const u8{

test "require pairing getter" {
    var guard1 = try PairingGuard.init(std.testing.allocator, true, &.{

test "pairing code is 6 chars" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "regenerate pairing code creates new code and resets lockout counters" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "set pairing code enforces provided 6-digit value" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "set pairing code rejects invalid format" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "is public bind empty string" {

test "is public bind ipv6 full form not public" {

test "constant time eq handles unicode bytes" {

test "constant time eq single char" {

test "constant time eq long strings" {
    const a = "abcdefghijklmnopqrstuvwxyz0123456789";
    const b = "abcdefghijklmnopqrstuvwxyz0123456789";

test "generate token length is 67" {
    const token = generateToken();

test "generate token is not deterministic" {
    var found_different = false;
        const t1 = generateToken();
        const t2 = generateToken();

test "is public bind various addresses" {
    // Private IP ranges that are still "public bind"
    // Hostname

test "token count starts at zero" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "is paired returns false when no tokens" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "is paired returns true with tokens" {
    const tokens = [_][]const u8{

// ── attemptPair tests ───────────────────────────────────────────

test "attemptPair returns missing_code when header absent" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "attemptPair succeeds with valid one-time code" {
    var guard = try PairingGuard.init(std.testing.allocator, true, &.{

test "attemptPair reports already_paired when no code is available" {
    const tokens = [_][]const u8{

test "attemptPair reports disabled when pairing is off" {
    var guard = try PairingGuard.init(std.testing.allocator, false, &.{
