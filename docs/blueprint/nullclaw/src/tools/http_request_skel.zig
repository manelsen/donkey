const builtin = @import("builtin");
const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const net_security = @import("../root.zig").net_security;
const http_util = @import("../http_util.zig");

const log = std.log.scoped(.http_request);

/// HTTP request tool for API interactions.
/// Supports GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS methods with
/// domain allowlisting, SSRF protection, and header redaction.
pub const HttpRequestTool = struct {

fn methodToSlice(method: std.http.Method) []const u8

fn shouldUseCurlResolve(host: []const u8) bool

fn shouldUsePinnedResolve(host: []const u8, connect_host: []const u8) bool

    const host_for_resolve = net_security.stripHostBrackets(host);



    var argv_buf: [64][]const u8 = undefined;
    var argc: usize = 0;
    const reserved_tail_args: usize = if (body != null) 5 else 3;


    var resolve_entry: ?[]u8 = null;

    var header_lines: std.ArrayListUnmanaged([]u8) = .empty;

        // Reserve room for trailing args:
        // -w "\n%{http_code}" <url> and optional --data-binary @-
        const line = try std.fmt.allocPrint(allocator, "{



    var child = std.process.Child.init(argv_buf[0..argc], allocator);


    const cancel_flag = http_util.currentThreadInterruptFlag();
    const AtomicBool = std.atomic.Value(bool);
    const CancelCtx = struct {
    const watcherFn = struct {
    var done = AtomicBool.init(false);
    var watcher: ?std.Thread = null;
    var cancel_ctx: CancelCtx = undefined;




    var stderr_copy: ?[]u8 = try duplicateTrimmedStderr(allocator, stderr_raw);

    const term = child.wait() catch return if (cancel_flag != null and cancel_flag.?.load(.acquire)) error.CurlInterrupted else error.CurlWaitError;


    const status_raw = std.mem.trim(u8, stdout[status_sep + 1 ..], " \t\r\n");
    const body_slice = stdout[0..status_sep];
    const response_body = try allocator.dupe(u8, body_slice);


fn duplicateTrimmedStderr(allocator: std.mem.Allocator, raw: ?[]const u8) !?[]u8

fn ensureTlsCaBundleLoaded(client: *std.http.Client) !void

fn isTlsSetupError(err: anyerror) bool

fn buildHttpRequestErrorMessage(allocator: std.mem.Allocator, prefix: []const u8, err: anyerror) ![]u8

fn validateMethod(method: []const u8) ?std.http.Method

/// Disable auto-follow redirects so every hop can be explicitly validated.

/// Parse headers from a JSON object string: {"Key": "Value", ...}
/// Returns array of [2][]const u8 pairs. Caller owns memory.
fn parseHeaders(allocator: std.mem.Allocator, headers_json: ?[]const u8) ![]const [2][]const u8

/// Redact sensitive headers for display output.
/// Headers with names containing authorization, api-key, apikey, token, secret,
/// or password (case-insensitive) get their values replaced with "***REDACTED***".
fn redactHeadersForDisplay(allocator: std.mem.Allocator, headers: []const [2][]const u8) ![]const u8

/// Check if a header name is sensitive (case-insensitive substring check).
fn isSensitiveHeader(name: []const u8) bool

// ── Tests ───────────────────────────────────────────────────────────

test "http_request tool name" {
    var ht = HttpRequestTool{

test "http_request tool description not empty" {
    var ht = HttpRequestTool{

test "http_request schema has url" {
    var ht = HttpRequestTool{

test "http_request schema has headers" {
    var ht = HttpRequestTool{

test "validateMethod accepts valid methods" {

test "validateMethod rejects invalid" {

// ── redactHeadersForDisplay tests ──────────────────────────

test "redactHeadersForDisplay redacts Authorization" {
    const result = try redactHeadersForDisplay(std.testing.allocator, &headers);

test "redactHeadersForDisplay preserves Content-Type" {
    const result = try redactHeadersForDisplay(std.testing.allocator, &headers);

test "redactHeadersForDisplay redacts api-key and token" {
    const result = try redactHeadersForDisplay(std.testing.allocator, &headers);

test "redactHeadersForDisplay empty returns empty" {
    const result = try redactHeadersForDisplay(std.testing.allocator, &.{

test "isSensitiveHeader checks" {

test "isSensitiveHeader treats oversized names as sensitive" {
    var long_name: [300]u8 = undefined;

test "http_request disables automatic redirects" {
    const opts = buildRequestOptions(&.{

test "http_request request options keep provided connection" {
    const fake_ptr_value = @as(usize, @alignOf(std.http.Client.Connection));
    const fake_connection: *std.http.Client.Connection = @ptrFromInt(fake_ptr_value);
    const opts = buildRequestOptions(&.{

// ── execute-level tests ──────────────────────────────────────

test "execute rejects missing url parameter" {
    var ht = HttpRequestTool{

test "execute rejects non-http scheme" {
    var ht = HttpRequestTool{

test "execute rejects localhost SSRF" {
    var ht = HttpRequestTool{

test "execute rejects localhost SSRF with URL userinfo" {
    var ht = HttpRequestTool{

test "execute rejects localhost SSRF with unbracketed ipv6 authority" {
    var ht = HttpRequestTool{

test "execute rejects private IP SSRF" {
    var ht = HttpRequestTool{

test "execute rejects 10.x private range" {
    var ht = HttpRequestTool{

test "execute rejects loopback decimal alias SSRF" {
    var ht = HttpRequestTool{

test "execute rejects unsupported method" {
    var ht = HttpRequestTool{

test "execute rejects invalid URL format" {
    var ht = HttpRequestTool{

test "execute rejects non-allowlisted domain" {
    const domains = [_][]const u8{

// ── Allowlist SSRF bypass tests (Issue #393) ───────────────

test "execute allows allowlisted private IP (fixes #393)" {
    // When a domain is in the allowlist, SSRF protection is skipped,
    // allowing access to private IPs (e.g., local searxng instance)
    const domains = [_][]const u8{

test "execute rejects non-allowlisted domain before DNS resolution" {
    // Non-allowlisted domains should be rejected immediately without DNS lookup
    const domains = [_][]const u8{

test "http_request parameters JSON is valid" {
    var ht = HttpRequestTool{