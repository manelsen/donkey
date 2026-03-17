//! Unified OAuth 2.0 module — PKCE, device code flow, credential store.
//!
//! Provides reusable OAuth primitives for all providers:
//! - PKCE challenge generation (RFC 7636)
//! - Token storage with filesystem-based credential store (~/.nullclaw/auth.json)
//! - Device Authorization Grant flow (RFC 8628)

const std = @import("std");
const platform = @import("platform.zig");
const json_util = @import("json_util.zig");

// ── PKCE (RFC 7636) ────────────────────────────────────────────────────

pub const PkceChallenge = struct {

/// Generate a PKCE challenge pair (RFC 7636).
/// 64 random bytes → base64url (no padding) verifier.
/// SHA-256(verifier) → base64url (no padding) challenge.
pub fn generatePkce(allocator: std.mem.Allocator) !PkceChallenge

/// Base64url-encode without padding, returning an allocated slice.
fn base64UrlEncodeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8

// ── OAuth Token ────────────────────────────────────────────────────────

pub const OAuthToken = struct {
    /// Returns true if the token is expired or within 300s of expiring.

// ── Credential Store ───────────────────────────────────────────────────

const CRED_DIR = ".nullclaw";
const CRED_FILE = "auth.json";

fn writeCredentialsFileAtomic(allocator: std.mem.Allocator, file_path: []const u8, contents: []const u8) !void

/// Save a credential for the given provider to ~/.nullclaw/auth.json.
/// Merges with existing credentials (other providers are preserved).
/// File permissions are set to 0o600.
pub fn saveCredential(allocator: std.mem.Allocator, provider: []const u8, token: OAuthToken) !void

/// Load a credential for the given provider from ~/.nullclaw/auth.json.
/// Returns null if the file is missing, the provider is not found, or the token
/// is expired and cannot be refreshed.
pub fn loadCredential(allocator: std.mem.Allocator, provider: []const u8) !?OAuthToken

const StoredToken = struct {

fn freeStoredToken(allocator: std.mem.Allocator, tok: StoredToken) void

fn loadAllCredentials(allocator: std.mem.Allocator, file_path: []const u8) ?std.StringArrayHashMap(StoredToken)

// ── Token Refresh ─────────────────────────────────────────────────────

/// Refresh an OAuth access token using a refresh_token grant.
/// Preserves the old refresh_token if the response omits a new one.
    var client: std.http.Client = .{

// ── Credential Deletion ───────────────────────────────────────────────

/// Delete a credential for the given provider from ~/.nullclaw/auth.json.
/// Returns true if the credential was found and removed.
pub fn deleteCredential(allocator: std.mem.Allocator, provider: []const u8) !bool

// ── Device Code Flow (RFC 8628) ────────────────────────────────────────

pub const DeviceCode = struct {

/// Initiate a device code flow by POSTing to the device authorization URL.
    var client: std.http.Client = .{

fn parseDeviceCodeResponse(allocator: std.mem.Allocator, body: []const u8) !DeviceCode

/// Poll the token endpoint until the user authorizes the device.
/// Returns the OAuthToken on success or error on timeout / denied.
    var client: std.http.Client = .{

fn parseTokenResponse(allocator: std.mem.Allocator, body: []const u8) !OAuthToken

// ════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════

test "PKCE verifier length is 86 chars (64 bytes base64url no-pad)" {
    const pkce = try generatePkce(std.testing.allocator);

    // 64 bytes → base64url no-pad = ceil(64*4/3) = 86 chars

test "PKCE challenge is 43 chars (32 bytes SHA-256 base64url no-pad)" {
    const pkce = try generatePkce(std.testing.allocator);

    // SHA-256 = 32 bytes → base64url no-pad = ceil(32*4/3) = 43 chars

test "PKCE challenge is valid base64url" {
    const pkce = try generatePkce(std.testing.allocator);


test "PKCE method is S256" {
    const pkce = try generatePkce(std.testing.allocator);

test "PKCE challenge matches SHA-256 of verifier" {
    const pkce = try generatePkce(std.testing.allocator);

    var hash: [32]u8 = undefined;
    const expected = try base64UrlEncodeAlloc(std.testing.allocator, &hash);


test "OAuthToken isExpired returns true for past expiry" {

test "OAuthToken isExpired returns false for far-future expiry" {

test "OAuthToken isExpired returns false when expires_at is zero" {

test "OAuthToken isExpired buffer: token expiring in 200s is expired" {
    // 200s < 300s buffer → should be expired

test "OAuthToken isExpired buffer: token expiring in 400s is NOT expired" {
    // 400s > 300s buffer → not expired

test "parseDeviceCodeResponse parses valid response" {
    const dc = try parseDeviceCodeResponse(std.testing.allocator, body);


test "parseDeviceCodeResponse handles verification_url alias" {
    const dc = try parseDeviceCodeResponse(std.testing.allocator, body);

test "parseDeviceCodeResponse defaults for missing interval/expires_in" {
    const dc = try parseDeviceCodeResponse(std.testing.allocator, body);

test "parseDeviceCodeResponse fails on missing device_code" {

test "parseTokenResponse parses valid token" {
    const token = try parseTokenResponse(std.testing.allocator, body);


test "parseTokenResponse fails on missing access_token" {

test "base64UrlEncodeAlloc produces correct output" {
    const input = "hello";
    const encoded = try base64UrlEncodeAlloc(std.testing.allocator, input);

test "parseTokenResponse preserves refresh_token in refresh response" {
    // Simulates a refresh response that includes a new refresh_token
    const token = try parseTokenResponse(std.testing.allocator, body);


test "parseTokenResponse handles missing refresh_token in response" {
    const token = try parseTokenResponse(std.testing.allocator, body);


test "Allocating writer deinit frees full buffer — no invalid free on sub-slice (issue #42)" {
    const allocator = std.testing.allocator;

    // Simulate the pattern from refreshAccessToken / pollDeviceCode:
    // Io.Writer.Allocating grows geometrically, so capacity > written length.
    // The old code did allocator.free(buffer[0..end]) — a sub-slice free
    // that is UB (length mismatch). The fix uses aw.deinit() instead.
        var aw: std.Io.Writer.Allocating = .init(allocator);


        // Confirm geometric growth: capacity > written

        const resp_body = aw.writer.buffer[0..aw.writer.end];
        const token = try parseTokenResponse(allocator, resp_body);


    // Same pattern for parseDeviceCodeResponse (startDeviceCodeFlow path)
        var aw: std.Io.Writer.Allocating = .init(allocator);



        const resp_body = aw.writer.buffer[0..aw.writer.end];
        const dc = try parseDeviceCodeResponse(allocator, resp_body);

    // If we reach here without panic, DebugAllocator confirmed:
    // 1. No invalid free (sub-slice length mismatch)
    // 2. No memory leak (all allocations freed)
