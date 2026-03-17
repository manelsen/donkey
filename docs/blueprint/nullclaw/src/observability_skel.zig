const std = @import("std");
const Atomic = @import("portable_atomic.zig").Atomic;

/// Events the observer can record.

/// Numeric metrics.

/// Core observability interface — Zig vtable pattern.
pub const Observer = struct {

const MAX_TOOL_CALL_DETAIL_LEN: usize = 256;

fn detailForObserver(detail: ?[]const u8) ?[]const u8

// ── NoopObserver ─────────────────────────────────────────────────────

/// Zero-overhead observer — all methods are no-ops.
pub const NoopObserver = struct {

// ── LogObserver ──────────────────────────────────────────────────────

/// Log-based observer — uses std.log for all output.
pub const LogObserver = struct {

// ── VerboseObserver ──────────────────────────────────────────────────

/// Human-readable progress observer for interactive CLI sessions.
pub const VerboseObserver = struct {

// ── MultiObserver ────────────────────────────────────────────────────

/// Fan-out observer — distributes events to multiple backends.
pub const MultiObserver = struct {

// ── FileObserver ─────────────────────────────────────────────────────

/// Appends events as JSONL to a log file.
pub const FileObserver = struct {

/// Factory: create observer from config backend string.
fn createObserver(backend: []const u8) []const u8

// ── OtelObserver ─────────────────────────────────────────────────────

/// OpenTelemetry key-value attribute.
pub const OtelAttribute = struct {

/// A single OTLP span with timing and attributes.
pub const OtelSpan = struct {

const http_util = @import("http_util.zig");

/// OpenTelemetry OTLP/HTTP observer — batches spans and exports via JSON.
pub const OtelObserver = struct {

// ── Tests ────────────────────────────────────────────────────────────

test "NoopObserver name" {
    var noop = NoopObserver{

test "NoopObserver does not panic on events" {
    var noop = NoopObserver{

test "LogObserver name" {
    var log_obs = LogObserver{

test "LogObserver does not panic on events" {
    var log_obs = LogObserver{

test "VerboseObserver name" {
    var verbose = VerboseObserver{

test "MultiObserver name" {
    var multi = MultiObserver{

test "MultiObserver empty does not panic" {
    var multi = MultiObserver{

test "MultiObserver fans out events" {
    var noop1 = NoopObserver{

test "createObserver factory" {

test "FileObserver name" {
    var file_obs = FileObserver{

test "FileObserver does not panic on events" {
    var file_obs = FileObserver{

test "FileObserver handles all event types" {
    var file_obs = FileObserver{

test "FileObserver tool_call detail is persisted as JSON string" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

// ── Additional observability tests ──────────────────────────────

test "VerboseObserver does not panic on events" {
    var verbose = VerboseObserver{

test "VerboseObserver handles all event types" {
    var verbose = VerboseObserver{

test "MultiObserver fans out metrics" {
    var noop1 = NoopObserver{

test "MultiObserver fans out flush" {
    var noop1 = NoopObserver{

test "ObserverEvent agent_start fields" {
    const event = ObserverEvent{

test "ObserverEvent agent_end fields" {
    const event = ObserverEvent{

test "ObserverEvent err fields" {
    const event = ObserverEvent{

test "ObserverEvent tool_call detail defaults to null" {
    const event = ObserverEvent{

test "ObserverEvent tool_call detail carries failure context" {
    const event = ObserverEvent{

test "ObserverMetric variants" {
    const m1 = ObserverMetric{

test "LogObserver handles failed llm_response" {
    var log_obs = LogObserver{

test "NoopObserver all metrics no-op" {
    var noop = NoopObserver{

test "MultiObserver with single observer" {
    var noop = NoopObserver{

test "createObserver case sensitive" {

test "Observer interface dispatches correctly" {
    // Verify the vtable pattern works through the Observer interface
    var noop = NoopObserver{

// ── OtelObserver tests ──────────────────────────────────────────

test "OtelObserver name" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

test "OtelObserver init defaults" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);

test "OtelObserver init custom endpoint" {
    var otel = OtelObserver.init(std.testing.allocator, "http://otel:4318", "myservice");

test "OtelObserver span building on agent_start" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    const event = ObserverEvent{

test "OtelObserver span building on all event types" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    // Record 9 events (under batch threshold of 10) to verify all types produce spans


    // Verify agent_end works too (10th event triggers batch flush)
    const end_event = ObserverEvent{

test "OtelObserver span attributes" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    const event = ObserverEvent{

test "OtelObserver tool_call includes detail attribute" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();


    const span = otel.spans.items[0];

    var found_detail = false;

test "OtelObserver spans keep independent attribute values" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();



    const first_span = otel.spans.items[0];
    const second_span = otel.spans.items[1];

    var first_duration: ?[]const u8 = null;
    var second_duration: ?[]const u8 = null;
    var first_detail: ?[]const u8 = null;
    var second_detail: ?[]const u8 = null;



test "OtelObserver JSON serialization escapes tool_call detail" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    const start = ObserverEvent{

test "OtelObserver JSON serialization" {
    var otel = OtelObserver.init(std.testing.allocator, null, "test-svc");
    const obs = otel.observer();

    const event = ObserverEvent{

test "OtelObserver JSON multiple spans" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    const e1 = ObserverEvent{

test "OtelObserver batch flush at 10 spans" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    // Record 9 events — should not flush
        const event = ObserverEvent{

    // 10th event triggers flush attempt (curl fails, spans get cleared anyway)
    const event = ObserverEvent{

test "OtelObserver metrics create spans" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    const m1 = ObserverMetric{

test "OtelObserver flush empty is noop" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();
    // Flush with no spans should not panic or leak

test "OtelObserver randomHex produces valid hex" {
    var buf: [32]u8 = undefined;

test "OtelObserver span timing" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    const event = ObserverEvent{

test "OtelObserver llm_response has duration-adjusted start" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();


    const span = otel.spans.items[0];
    // start should be earlier than end by ~100ms

test "OtelObserver vtable through Observer interface" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    // Verify it works through the generic Observer interface
    const event = ObserverEvent{

test "OtelObserver requests_total counter" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();


    const e1 = ObserverEvent{

test "OtelObserver errors_total counter on failed response" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();


    // Successful response should not increment errors
    const ok = ObserverEvent{

test "OtelObserver errors_total counter on error event" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    const e1 = ObserverEvent{

test "OtelObserver JSON includes status code" {
    var otel = OtelObserver.init(std.testing.allocator, null, "svc");
    const obs = otel.observer();

    const event = ObserverEvent{

test "OtelObserver counters combined scenario" {
    var otel = OtelObserver.init(std.testing.allocator, null, null);
    const obs = otel.observer();

    // 3 requests, 1 failed response, 2 errors
    const req = ObserverEvent{
