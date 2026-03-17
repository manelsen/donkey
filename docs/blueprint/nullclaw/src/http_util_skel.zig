//! Shared HTTP utilities via curl subprocess.
//!
//! Replaces 9+ local `curlPost` / `curlGet` duplicates across the codebase.
//! Uses curl to avoid Zig 0.15 std.http.Client segfaults.

const std = @import("std");
const Allocator = std.mem.Allocator;
const AtomicBool = std.atomic.Value(bool);

const log = std.log.scoped(.http_util);
threadlocal var thread_interrupt_flag: ?*const AtomicBool = null;
const DEFAULT_CURL_GET_MAX_BYTES: usize = 4 * 1024 * 1024;
const DEFAULT_CURL_POST_MAX_BYTES: usize = 8 * 1024 * 1024;

fn classifyCurlExitCode(code: u8) []const u8

fn mapCurlExitCodeToError(code: u8) anyerror

fn logCurlExitFailure(op: []const u8, code: u8) void

pub fn setThreadInterruptFlag(flag: ?*const AtomicBool) void

pub fn currentThreadInterruptFlag() ?*const AtomicBool

const CancelWatcherCtx = struct {

fn cancelWatcherMain(ctx: *CancelWatcherCtx) void

pub const HttpResponse = struct {

pub const HttpResponseWithHeaders = struct {

/// HTTP POST via curl subprocess with optional proxy and timeout.
///
/// `headers` is a slice of header strings (e.g. `"Authorization: Bearer xxx"`).
/// `proxy` is an optional proxy URL (e.g. `"socks5://host:port"`).
/// `max_time` is an optional --max-time value as a string (e.g. `"300"`).
/// Returns the response body. Caller owns returned memory.

/// HTTP POST with application/x-www-form-urlencoded body via curl subprocess,
/// with optional proxy and timeout.

    var argv_buf: [40][]const u8 = undefined;
    var argc: usize = 0;





    // Pass payload via stdin to avoid OS argv length limits for large JSON
    // bodies (e.g. multimodal base64 images).

    var child = std.process.Child.init(argv_buf[0..argc], allocator);

    const cancel_flag = thread_interrupt_flag;
    var cancel_done = AtomicBool.init(false);
    var cancel_watcher: ?std.Thread = null;
    var watcher_ctx: CancelWatcherCtx = undefined;





/// HTTP POST via curl subprocess (no proxy, no timeout).
pub fn curlPost(allocator: Allocator, url: []const u8, body: []const u8, headers: []const []const u8) ![]u8

/// HTTP POST with application/x-www-form-urlencoded body via curl subprocess.
///
/// `body` must already be percent-encoded form data (e.g. `"key=val&key2=val2"`).
/// Returns the response body. Caller owns returned memory.
pub fn curlPostForm(allocator: Allocator, url: []const u8, body: []const u8) ![]u8

/// HTTP POST via curl subprocess and include HTTP status code in response.
/// Caller owns `response.body`.

/// HTTP POST via curl subprocess and include HTTP status code in response,
/// with optional --max-time timeout.
/// Caller owns `response.body`.
    var argv_buf: [48][]const u8 = undefined;
    var argc: usize = 0;






    var child = std.process.Child.init(argv_buf[0..argc], allocator);

    const cancel_flag = thread_interrupt_flag;
    var cancel_done = AtomicBool.init(false);
    var cancel_watcher: ?std.Thread = null;
    var watcher_ctx: CancelWatcherCtx = undefined;




    const status_sep = std.mem.lastIndexOfScalar(u8, stdout, '\n') orelse return error.CurlParseError;
    const status_raw = std.mem.trim(u8, stdout[status_sep + 1 ..], " \t\r\n");
    const status_code = std.fmt.parseInt(u16, status_raw, 10) catch return error.CurlParseError;
    const body_slice = stdout[0..status_sep];
    const response_body = try allocator.dupe(u8, body_slice);


/// HTTP POST via curl subprocess and include HTTP status code and response headers,
/// with optional --max-time timeout.
/// Caller owns `response.headers` and `response.body`.
    var argv_buf: [56][]const u8 = undefined;
    var argc: usize = 0;





    // Dump response headers to stdout so we can capture session IDs.


    var child = std.process.Child.init(argv_buf[0..argc], allocator);

    const cancel_flag = thread_interrupt_flag;
    var cancel_done = AtomicBool.init(false);
    var cancel_watcher: ?std.Thread = null;
    var watcher_ctx: CancelWatcherCtx = undefined;




    const status_sep = std.mem.lastIndexOfScalar(u8, stdout, '\n') orelse return error.CurlParseError;
    const status_raw = std.mem.trim(u8, stdout[status_sep + 1 ..], " \t\r\n");
    const status_code = std.fmt.parseInt(u16, status_raw, 10) catch return error.CurlParseError;

    const payload = stdout[0..status_sep];
    const header_end_crlf = std.mem.indexOf(u8, payload, "\r\n\r\n");
    const header_end_lf = std.mem.indexOf(u8, payload, "\n\n");

    var headers_slice: []const u8 = "";
    var body_slice: []const u8 = payload;


    const headers_out = try allocator.dupe(u8, headers_slice);
    const body_out = try allocator.dupe(u8, body_slice);



/// HTTP PUT via curl subprocess (no proxy, no timeout).
pub fn curlPut(allocator: Allocator, url: []const u8, body: []const u8, headers: []const []const u8) ![]u8

/// HTTP GET via curl subprocess with optional proxy.
///
/// `headers` is a slice of header strings (e.g. `"Authorization: Bearer xxx"`).
/// `timeout_secs` sets --max-time. Returns the response body. Caller owns returned memory.
    var argv_buf: [48][]const u8 = undefined;
    var argc: usize = 0;






    var child = std.process.Child.init(argv_buf[0..argc], allocator);

    const cancel_flag = thread_interrupt_flag;
    var cancel_done = AtomicBool.init(false);
    var cancel_watcher: ?std.Thread = null;
    var watcher_ctx: CancelWatcherCtx = undefined;




/// HTTP GET via curl subprocess with optional proxy.
///
/// `headers` is a slice of header strings (e.g. `"Authorization: Bearer xxx"`).
/// `timeout_secs` sets --max-time. Returns the response body. Caller owns returned memory.

/// HTTP GET via curl subprocess with a pinned host mapping.
///
/// `resolve_entry` must be in curl `--resolve` format: `host:port:address`.

/// HTTP GET via curl subprocess (no proxy).
pub fn curlGet(allocator: Allocator, url: []const u8, headers: []const []const u8, timeout_secs: []const u8) ![]u8

/// HTTP GET via curl subprocess with a caller-provided response size cap.

/// Read proxy URL from standard environment variables.
/// Checks HTTPS_PROXY, HTTP_PROXY, ALL_PROXY in that order.
/// Returns null if no proxy is set.
/// Caller owns returned memory.
var proxy_override_value: ?[]u8 = null;
var proxy_override_mutex: std.Thread.Mutex = .{