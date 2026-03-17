//! Tools module — agent tool integrations for LLM function calling.
//!
//! Provides a common Tool vtable, ToolResult/ToolSpec types, and implementations
//! for shell execution, file I/O, HTTP requests, git operations, memory tools,
//! scheduling, delegation, browser, and image tools.

const std = @import("std");
const memory_mod = @import("../memory/root.zig");
const Memory = memory_mod.Memory;
const bootstrap_mod = @import("../bootstrap/root.zig");
const mcp_mod = @import("../mcp.zig");

// ── JSON arg extraction helpers ─────────────────────────────────
// Used by all tool implementations to extract typed fields from
// the pre-parsed ObjectMap passed by the dispatcher.

pub const JsonObjectMap = std.json.ObjectMap;
pub const JsonValue = std.json.Value;

pub fn getString(args: JsonObjectMap, key: []const u8) ?[]const u8

pub fn getBool(args: JsonObjectMap, key: []const u8) ?bool

pub fn getInt(args: JsonObjectMap, key: []const u8) ?i64

pub fn getValue(args: JsonObjectMap, key: []const u8) ?JsonValue

pub fn getStringArray(args: JsonObjectMap, key: []const u8) ?[]const JsonValue

/// Test helper: parse a JSON string into a Parsed(Value) for use in tool tests.
/// The caller must `defer parsed.deinit()` and extract `.value.object` for the ObjectMap.
pub fn parseTestArgs(json_str: []const u8) !std.json.Parsed(JsonValue)

// Sub-modules
pub const shell = @import("shell.zig");
pub const file_read = @import("file_read.zig");
pub const file_write = @import("file_write.zig");
pub const file_edit = @import("file_edit.zig");
pub const file_delete = @import("file_delete.zig");
pub const file_read_hashed = @import("file_read_hashed.zig");
pub const file_edit_hashed = @import("file_edit_hashed.zig");
pub const http_request = @import("http_request.zig");
pub const git = @import("git.zig");
pub const memory_store = @import("memory_store.zig");
pub const memory_recall = @import("memory_recall.zig");
pub const memory_list = @import("memory_list.zig");
pub const memory_forget = @import("memory_forget.zig");
pub const schedule = @import("schedule.zig");
pub const delegate = @import("delegate.zig");
pub const browser = @import("browser.zig");
pub const image = @import("image.zig");
pub const composio = @import("composio.zig");
pub const screenshot = @import("screenshot.zig");
pub const browser_open = @import("browser_open.zig");
pub const hardware_info = @import("hardware_info.zig");
pub const hardware_memory = @import("hardware_memory.zig");
pub const cron_add = @import("cron_add.zig");
pub const cron_list = @import("cron_list.zig");
pub const cron_remove = @import("cron_remove.zig");
pub const cron_runs = @import("cron_runs.zig");
pub const cron_run = @import("cron_run.zig");
pub const cron_update = @import("cron_update.zig");
pub const message = @import("message.zig");
pub const pushover = @import("pushover.zig");
pub const schema = @import("schema.zig");
pub const web_search = @import("web_search.zig");
pub const web_fetch = @import("web_fetch.zig");
pub const file_append = @import("file_append.zig");
pub const spawn = @import("spawn.zig");
pub const i2c = @import("i2c.zig");
pub const spi = @import("spi.zig");
pub const path_security = @import("path_security.zig");
pub const process_util = @import("process_util.zig");

// ── Core types ──────────────────────────────────────────────────────

/// Result of a tool execution.
///
/// Ownership: both `output` and `error_msg` are owned by the tool that produced them.
/// The caller (agent/dispatcher) must free them with `allocator.free()` after use.
/// Exception: static string literals (e.g. `""`, compile-time constants) must NOT be freed —
/// use `ToolResult.ok("")` or `ToolResult.fail("literal")` for those.
pub const ToolResult = struct {
    /// Heap-allocated output string owned by caller. Free with allocator.free().
    /// May be an empty literal "" for void results — do NOT free in that case.
    /// Heap-allocated error message owned by caller if non-null. Free with allocator.free().
    /// Create a success result with a static/literal output (do NOT free).

/// Description of a tool for the LLM (function calling schema)
pub const ToolSpec = struct {

/// Tool vtable — implement for any capability.
/// Uses Zig's type-erased interface pattern.
pub const Tool = struct {

/// Generate a Tool.VTable from a tool struct type at comptime.
///
/// The type T must declare:
///   - `pub const tool_name: []const u8`
///   - `pub const tool_description: []const u8`
///   - `pub const tool_params: []const u8`
///   - `fn execute(self: *T, allocator: Allocator, args: JsonObjectMap) anyerror!ToolResult`
pub fn ToolVTable(comptime T: type) Tool.VTable

/// Comptime check that a type correctly implements the Tool interface.
pub fn assertToolInterface(comptime T: type) void

/// Create the default tool set (shell, file_read, file_write).

/// Create the default tool set with additional allowed paths.
    var list: std.ArrayList(Tool) = .{

/// Create all tools including optional ones.
    var list: std.ArrayList(Tool) = .{

/// Bind a memory backend to memory tools in a pre-built tool list.
pub fn bindMemoryTools(tools: []const Tool, memory: ?Memory) void

/// Bind a MemoryRuntime to memory tools for retrieval pipeline and vector sync.
/// Call after bindMemoryTools to enable hybrid search and vector sync.
pub fn bindMemoryRuntime(tools: []const Tool, mem_rt: ?*memory_mod.MemoryRuntime) void

/// Free all heap-allocated tool structs and the tools slice itself.
/// Pairs with `allTools` / `defaultTools` / `subagentTools`.
pub fn deinitTools(allocator: std.mem.Allocator, tools: []const Tool) void

/// Create restricted tool set for subagents.
/// Includes: shell, file_read, file_write, file_edit, file_read_hashed,
/// file_edit_hashed, git, http (if enabled).
/// Excludes: message, spawn, delegate, schedule, memory, composio, browser —
/// to prevent infinite loops and cross-channel side effects.
    var list: std.ArrayList(Tool) = .{

// ── Tests ───────────────────────────────────────────────────────────

test "getString returns unescaped newlines and tabs" {
    const parsed = try parseTestArgs("{

test "getString returns unescaped quotes and backslashes" {
    const parsed = try parseTestArgs("{

test "getString returns unescaped unicode" {
    // \u0041 = A, \u00c9 = É
    const parsed = try parseTestArgs("{

test "getString returns unescaped shell script content" {
    const parsed = try parseTestArgs("{

test "getString returns null for missing key" {
    const parsed = try parseTestArgs("{

test "getString returns null for non-string value" {
    const parsed = try parseTestArgs("{

test "getBool extracts boolean values" {
    const parsed = try parseTestArgs("{

test "getInt extracts integer values" {
    const parsed = try parseTestArgs("{

test "tool result ok" {
    const r = ToolResult.ok("hello");

test "tool result fail" {
    const r = ToolResult.fail("boom");

test "default tools returns four" {
    const tools = try defaultTools(std.testing.allocator, "/tmp/yc_test");
        // Free the heap-allocated tool structs

    // Verify names

test "all tools has descriptions" {
    const tools = try defaultTools(std.testing.allocator, "/tmp/yc_test");

test "all tools have parameter schemas" {
    const tools = try defaultTools(std.testing.allocator, "/tmp/yc_test");
        const json = t.parametersJson();
        // Should be valid JSON object

test "tool spec generation" {
    const tools = try defaultTools(std.testing.allocator, "/tmp/yc_test");
        const s = t.spec();

test "all tools includes extras when enabled" {

    // Order: shell, file_read, file_write, file_edit, file_delete, file_read_hashed, file_edit_hashed, git, image_info,
    //        memory_store, memory_recall, memory_list, memory_forget,
    //        delegate, schedule, spawn, pushover, http_request, web_search,
    //        web_fetch, browser = 21

test "all tools excludes extras when disabled" {
    const tools = try allTools(std.testing.allocator, "/tmp/yc_test", .{

test "all tools wires http and web_search config into tool instances" {
    const domains = [_][]const u8{

test "all tools wire bootstrap provider into file_read for sqlite backends" {
    var tmp_dir = std.testing.tmpDir(.{

test "all tools wires subagent manager into spawn tool" {
    const Config = @import("../config.zig").Config;
    const subagent_mod = @import("../subagent.zig");

    var manager = subagent_mod.SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "subagent tools use configured shell and file limits" {

    var saw_shell = false;
    var saw_file_read = false;
    var saw_file_edit = false;
    var saw_file_read_hashed = false;
    var saw_file_edit_hashed = false;
            const st: *shell.ShellTool = @ptrCast(@alignCast(t.ptr));
            const ft: *file_read.FileReadTool = @ptrCast(@alignCast(t.ptr));
            const et: *file_edit.FileEditTool = @ptrCast(@alignCast(t.ptr));
            const ft: *file_read_hashed.FileReadHashedTool = @ptrCast(@alignCast(t.ptr));
            const et: *file_edit_hashed.FileEditHashedTool = @ptrCast(@alignCast(t.ptr));


test "subagent tools wire bootstrap provider into file_read for sqlite backends" {
    var tmp_dir = std.testing.tmpDir(.{

test "subagent tools wire http allowlist and response limit" {
    const domains = [_][]const u8{

test "bindMemoryTools matches by vtable, not by colliding tool name" {
    const FakeCollidingTool = struct {

    const NoneMemory = @import("../memory/root.zig").NoneMemory;
    var backend = NoneMemory.init();

    var real_memory_store = memory_store.MemoryStoreTool{

test {
