const std = @import("std");
const AtomicBool = std.atomic.Value(bool);
const builtin = @import("builtin");

// Win32 APIs used for codepage fallback decoding on Windows.



const CP_UTF8: std.os.windows.UINT = 65001;
const CP_GBK: std.os.windows.UINT = 936;
const MB_ERR_INVALID_CHARS: std.os.windows.DWORD = 0x00000008;

threadlocal var thread_interrupt_flag: ?*const AtomicBool = null;

pub fn setThreadInterruptFlag(flag: ?*const AtomicBool) void

/// Result of a child process execution.
pub const RunResult = struct {
    /// Free both stdout and stderr buffers.

/// Options for running a child process.
pub const RunOptions = struct {

const CancelWatcherCtx = struct {

fn cancelWatcherMain(ctx: *CancelWatcherCtx) void

fn appendUtf8Replacement(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void

fn lossilyNormalizeToUtf8(allocator: std.mem.Allocator, input: []const u8) ![]u8


    const in_len: i32 = std.math.cast(i32, input.len) orelse return null;
    // Keep UTF-8 strict so a console forced to CP_UTF8 does not swallow
    // ACP/GBK bytes with U+FFFD substitutions before we can try fallbacks.
    const decode_flags: std.os.windows.DWORD = if (code_page == CP_UTF8) MB_ERR_INVALID_CHARS else 0;

    const wide_len = MultiByteToWideChar(code_page, decode_flags, input.ptr, in_len, null, 0);

    const wide_len_usize: usize = @intCast(wide_len);
    const wide = try allocator.alloc(u16, wide_len_usize);


    const utf8_len = WideCharToMultiByte(CP_UTF8, 0, wide.ptr, wide_len, null, 0, null, null);

    const utf8_len_usize: usize = @intCast(utf8_len);
    const out = try allocator.alloc(u8, utf8_len_usize);



fn tryDecodeWindowsOutputToUtf8(allocator: std.mem.Allocator, input: []const u8) !?[]u8

fn normalizeCapturedOutputOwned(allocator: std.mem.Allocator, input: []u8) ![]u8

/// Run a child process, capture stdout and stderr, and return the result.
///
/// The caller owns the returned stdout and stderr buffers.
/// Use `result.deinit(allocator)` to free them.
    var child = std.process.Child.init(argv, allocator);


    const effective_cancel_flag = opts.cancel_flag orelse thread_interrupt_flag;
    var cancel_done = AtomicBool.init(false);
    var cancel_watcher: ?std.Thread = null;
    var watcher_ctx: CancelWatcherCtx = undefined;



    const term = try child.wait();
    const interrupted = if (effective_cancel_flag) |flag| flag.load(.acquire) else false;


// ── Tests ───────────────────────────────────────────────────────────

test "run echo returns stdout" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const result = try run(allocator, &.{

test "run failing command returns exit code" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const result = try run(allocator, &.{

test "run with cwd" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const result = try run(allocator, &.{

test "run honors cancel flag and interrupts child" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    var cancel = AtomicBool.init(false);

    const ThreadResult = struct {
    var thread_result = ThreadResult{

test "RunResult deinit frees buffers" {
    const allocator = std.testing.allocator;
    const stdout = try allocator.dupe(u8, "output");
    const stderr = try allocator.dupe(u8, "error");

test "RunResult deinit with empty buffers" {
    const allocator = std.testing.allocator;

test "normalizeCapturedOutputOwned converts invalid UTF-8 to safe text" {
    const allocator = std.testing.allocator;
    const invalid = try allocator.dupe(u8, &[_]u8{

test "run normalizes invalid stderr before returning" {
    const allocator = std.testing.allocator;
    const argv: []const []const u8 = if (comptime builtin.os.tag == .windows)

    const result = try run(allocator, argv, .{

test "windows gbk fallback decodes to utf8" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const gbk = [_]u8{

test "windows utf8 decoder rejects gbk bytes so ansi fallback can run" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const gbk = [_]u8{
