//! Standalone SSE (Server-Sent Events) streaming client.
//!
//! This module is kept separate from the rest of the codebase to avoid
//! Zig 0.15 namespace collision bugs when std.http is used alongside
//! modules that export 'http' symbols.
//!
//! Provides persistent SSE connections with chunked transfer encoding
//! support for real-time message delivery.

const std = @import("std");
const log = std.log.scoped(.sse_client);

/// Maximum SSE event size (256KB)
/// Events larger than this are truncated to prevent memory exhaustion
const MAX_EVENT_SIZE = 256 * 1024;

/// Maximum buffer size for read operations
/// Prevents buffer overflow attacks and memory exhaustion
const MAX_BUFFER_SIZE = 8192;

/// Maximum wait time for new bytes before returning to caller.
/// Keeps polling loops responsive to shutdown and reconnect signals.
const READ_TIMEOUT_MS: i32 = 1000;

/// SSE connection that maintains a persistent HTTP connection for streaming
pub const SseConnection = struct {
    /// The body reader for streaming response data
    /// Buffer for reading response data
    /// Last received event ID for reconnection (W3C SSE spec).
    /// Sent as Last-Event-ID header on reconnect so the server can resume.
    /// Initialize a new SSE connection (not yet connected)

/// SSE event data structure
pub const SseEvent = struct {
    /// Event type from the "event:" field (empty string means default "message").
    /// Owned by the caller; freed on deinit.
    /// Last event ID from the "id:" field (empty string if not set).
    /// Owned by the caller; freed on deinit.

/// Helper to transfer ownership of an ArrayList(u8) to a caller-owned slice,
/// or free the backing capacity if items are empty. Returns &.{} when empty.
fn ownOrFreeList(list: *std.ArrayList(u8), allocator: std.mem.Allocator) ![]u8

/// Parse SSE events from a buffer
/// Returns a slice of events (caller must free each event.data and the slice itself)
///
/// Safety: Truncates events larger than MAX_EVENT_SIZE to prevent memory exhaustion.
/// Events are delimited by double newlines (\n\n).
/// Each data: line contributes to the event data, with newlines preserved.
///
/// Per the W3C SSE specification:
/// - Lines starting with ":" are comments (ignored)
/// - Field names: "data", "event", "id", "retry"
/// - After "field:", exactly ONE leading space is stripped from the value
/// - Empty data: lines append an empty string (producing a newline in multi-line data)
pub fn parseEvents(allocator: std.mem.Allocator, buffer: []const u8) ![]SseEvent

/// Parse a single SSE line into field name and value.
/// Per the W3C spec: if the line contains ":", the field is everything before the first ":"
/// and the value is everything after, with exactly one leading space stripped if present.
/// If the line contains no ":", the entire line is the field name and value is empty.
fn parseField(line: []const u8) struct

fn freeEvents(allocator: std.mem.Allocator, events: []SseEvent) void

test "parseEvents extracts SSE data fields" {
    const allocator = std.testing.allocator;

    // Test basic SSE format: data: json\n\n
    const sse_data = "data:{

test "parseEvents skips comments" {
    const allocator = std.testing.allocator;

    const sse_data = ": comment\ndata:{

test "parseEvents handles multi-line data" {
    const allocator = std.testing.allocator;

    // Multi-line data should have newlines preserved
    const sse_data = "data: line1\ndata: line2\n\n";
    const events = try parseEvents(allocator, sse_data);


test "parseEvents parses event type and id fields" {
    const allocator = std.testing.allocator;

    const sse_data = "event: update\nid: 42\ndata: payload\n\n";
    const events = try parseEvents(allocator, sse_data);


test "parseEvents strips exactly one leading space from value" {
    const allocator = std.testing.allocator;

    // "data:  two spaces" should produce " two spaces" (one space stripped)
    const sse_data = "data:  two spaces\n\n";
    const events = try parseEvents(allocator, sse_data);


test "parseEvents handles data field with no value" {
    const allocator = std.testing.allocator;

    // "data:" followed by "data: content" should produce "\ncontent"
    const sse_data = "data:\ndata: content\n\n";
    const events = try parseEvents(allocator, sse_data);


test "parseEvents handles CRLF line endings" {
    const allocator = std.testing.allocator;

    const sse_data = "data: hello\r\n\r\n";
    const events = try parseEvents(allocator, sse_data);


test "parseField parses field:value correctly" {
    // Normal field with space
    const r1 = parseField("data: hello");

    // No space after colon
    const r2 = parseField("data:hello");

    // No colon — entire line is field name
    const r3 = parseField("data");

    // Empty value after colon
    const r4 = parseField("data:");
