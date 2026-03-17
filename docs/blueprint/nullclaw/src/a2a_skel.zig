//! A2A (Agent-to-Agent) protocol support for nullclaw.
//!
//! Implements Google's Agent-to-Agent protocol over JSON-RPC 2.0:
//!   - GET /.well-known/agent-card.json -> Agent Card discovery
//!   - POST /a2a -> JSON-RPC dispatch (message/send, message/stream, tasks/get, tasks/cancel, tasks/list)
//!
//! Task state machine: submitted -> working -> completed | failed | canceled | input-required

const std = @import("std");
const builtin = @import("builtin");
const Config = @import("config.zig").Config;
const gateway = @import("gateway.zig");
const ConversationContext = @import("agent/prompt.zig").ConversationContext;
const streaming = @import("streaming.zig");

/// Maximum number of tasks kept in the registry before eviction.
const MAX_TASKS: usize = 1000;
const A2A_PROTOCOL_VERSION = "0.2.5";

// ── Task State ──────────────────────────────────────────────────

pub const TaskState = enum {

// ── Task Record ─────────────────────────────────────────────────

pub const TaskRecord = struct {

pub const TaskSnapshot = struct {

fn deinitTaskSnapshots(allocator: std.mem.Allocator, tasks: []TaskSnapshot) void

fn isTerminalState(state: TaskState) bool

fn taskOrdinal(task_id: []const u8) u64

fn isTaskSnapshotMoreRecent(current: TaskSnapshot, previous: TaskSnapshot) bool

fn sortTaskSnapshotsByRecency(tasks: []TaskSnapshot) void

// ── Task Registry ───────────────────────────────────────────────

pub const TaskRegistry = struct {

// ── A2A Response ────────────────────────────────────────────────

pub const A2aResponse = struct {

// ── Handler: Agent Card ─────────────────────────────────────────

pub fn handleAgentCard(allocator: std.mem.Allocator, cfg: *const Config) A2aResponse

// ── Handler: JSON-RPC Dispatch ──────────────────────────────────


    // Extract JSON-RPC id — may be a string or number.
    const request_id = extractJsonRpcId(body) orelse "null";


// ── SSE Streaming ───────────────────────────────────────────────

/// Check if a JSON-RPC body contains a streaming method.
/// Used by the gateway to decide between normal and SSE response paths.
pub fn isStreamingMethod(body: []const u8) bool

/// SSE Sink context — writes JSON-RPC SSE events to a raw TCP stream.
pub const SseStreamCtx = struct {
    /// Write an SSE "data:" line with the given JSON payload.

/// Handle a streaming JSON-RPC request by writing SSE events directly to the TCP stream.
/// This bypasses the normal request/response cycle and writes directly.
/// The caller must NOT call writeJsonResponse after this.
    const request_id = extractJsonRpcId(body) orelse "null";

    const context_id = extractMessageContextId(body);


    // Write SSE headers.

    const initial_task_json = buildTaskJson(allocator, &task) catch return;
    const initial_event = buildJsonRpcResult(allocator, request_id, initial_task_json) catch return;

    // Mark as working after emitting the initial submitted task.
        var current_task = registry.getTaskSnapshot(allocator, task.id) catch return;
        const current_snapshot = current_task orelse return;
            const final_event = buildStatusUpdateEvent(allocator, request_id, current_snapshot.id, current_snapshot.context_id, current_snapshot.state, current_snapshot.updated_at, true) catch return;

    // Create SSE sink context.
    const sink = sse_ctx.makeSink();

    const context: ConversationContext = .{

/// Write an SSE error event to the stream context.
fn writeSseErrorEvent(allocator: std.mem.Allocator, sse_ctx: *SseStreamCtx, code: i32, message: []const u8) void

/// Write SSE headers and a single error event for pre-streaming failures.
fn writeSseError(allocator: std.mem.Allocator, stream: *std.net.Stream, request_id: []const u8, code: i32, message: []const u8) void

// ── Internal: Send Message ──────────────────────────────────────

    const context_id = extractMessageContextId(body);


    // Update state to working.

    const context: ConversationContext = .{

// ── Internal: Get Task ──────────────────────────────────────────


    var task = registry.getTaskSnapshot(allocator, task_id) catch return errorResponse();



// ── Internal: Cancel Task ───────────────────────────────────────


    var current_task = registry.getTaskSnapshot(allocator, task_id) catch return errorResponse();

    // Check if task is in a terminal state.

    // Request interruption if working.
        var result = session_mgr.requestTurnInterrupt(task.session_key);

    var canceled_task = registry.cancelTask(allocator, task_id) catch return errorResponse();



// ── Internal: List Tasks ────────────────────────────────────────

    // Parse optional filters from params.
    const params_section = extractParamsObject(body) orelse "{

// ── JSON Builder Helpers ────────────────────────────────────────

/// Build a JSON-RPC result response. `request_id` is a raw JSON token (e.g. `"1"` or `1`).
fn buildJsonRpcResult(allocator: std.mem.Allocator, request_id: []const u8, result_json: []const u8) ![]u8

/// Build a JSON-RPC error response. `request_id` is a raw JSON token (e.g. `"1"` or `1`).
fn buildJsonRpcError(allocator: std.mem.Allocator, request_id: []const u8, code: i32, message: []const u8) ![]u8

fn buildTaskJson(allocator: std.mem.Allocator, task: *const TaskSnapshot) ![]u8

/// Format a unix timestamp (seconds since epoch) as ISO 8601 UTC.
fn formatTimestamp(buf: *[32]u8, epoch_secs: i64) []const u8

fn buildEndpointUrl(allocator: std.mem.Allocator, base_url: []const u8) ![]u8

// ── Text Extraction Helpers ─────────────────────────────────────

fn skipJsonWhitespace(json: []const u8, start: usize) usize

fn scanJsonStringEnd(json: []const u8, start: usize) ?usize

fn scanJsonCompositeEnd(json: []const u8, start: usize, open: u8, close: u8) ?usize

fn scanJsonNumberEnd(json: []const u8, start: usize) ?usize

fn scanJsonLiteralEnd(json: []const u8, start: usize, literal: []const u8) ?usize

fn scanJsonValueEnd(json: []const u8, start: usize) ?usize

fn extractObjectStringField(object_json: []const u8, key: []const u8) ?[]const u8

fn extractObjectIntField(object_json: []const u8, key: []const u8) ?i64

fn extractObjectObjectField(object_json: []const u8, key: []const u8) ?[]const u8