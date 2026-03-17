const std = @import("std");

// Telegram draft previews are easy to rate-limit if we flush tiny deltas too
// aggressively. Use noticeably coarser thresholds so users still see progress
// without hammering sendMessageDraft on every token burst.
pub const DRAFT_FLUSH_MIN_DELTA_BYTES: usize = 512;
pub const DRAFT_FLUSH_MIN_INTERVAL_MS: i64 = 4 * std.time.ms_per_s;
pub const DRAFT_HEARTBEAT_INTERVAL_MS: i64 = 12 * std.time.ms_per_s;
pub const DRAFT_TRANSPORT_MAX_BYTES: usize = 3000;

const DRAFT_TRIM_BYTES = " \t\r\n";
const DRAFT_PROGRESS_PREFIX = "Processing request...\n";
const DRAFT_PROGRESS_TAIL_LABEL = "\n\nLatest excerpt:\n";
const DRAFT_PROGRESS_HEARTBEAT_ONLY = "Interim result is still being prepared.";

pub const DraftState = struct {

pub const DraftFlush = struct {

fn trimmedDraftText(text: []const u8) []const u8

pub fn hasVisibleDraftText(text: []const u8) bool

fn bytesSinceLastFlush(state: *const DraftState) usize

fn millisSinceLastFlush(state: *const DraftState, now_ms: i64) i64

fn flushDeltaReached(state: *const DraftState) bool

fn flushIntervalElapsed(state: *const DraftState, now_ms: i64) bool

fn draftSuppressed(state: *const DraftState, now_ms: i64) bool

fn shouldFlushDraft(state: *const DraftState, now_ms: i64) bool

fn hasPendingVisibleDraft(state: *const DraftState) bool

fn snapshotDraftText(allocator: std.mem.Allocator, state: *const DraftState) ![]u8

fn alignUtf8Start(text: []const u8, start: usize) usize

fn draftTailSlice(text: []const u8, max_bytes: usize) []const u8

fn appendElapsedSummary(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, text_len: usize, started_at_ms: i64, now_ms: i64) !void

pub fn buildHeartbeatText(allocator: std.mem.Allocator, started_at_ms: i64, now_ms: i64) ![]u8


    var prefix: std.ArrayListUnmanaged(u8) = .empty;


    const tail_budget = DRAFT_TRANSPORT_MAX_BYTES - prefix.items.len;
    const tail = draftTailSlice(text, tail_budget);

    var out: std.ArrayListUnmanaged(u8) = .empty;

fn markDraftFlushed(state: *DraftState, now_ms: i64) void



    const text = try snapshotDraftText(allocator, state);


        const text = try snapshotDraftText(allocator, state);



pub fn suppressDraft(state: *DraftState, now_ms: i64, retry_after_secs: u32) void

pub fn suppressDraftUntilMs(state: *DraftState, suppress_until_ms: i64) void

        var draft = entry.value;

    var it = draft_buffers.iterator();

test "appendDraftChunk ignores empty chunks" {
    var draft: DraftState = .{

test "appendDraftChunk keeps whitespace-only drafts local" {
    var draft: DraftState = .{

test "appendDraftChunk flushes visible content after interval" {
    var draft: DraftState = .{

test "appendDraftChunk stays quiet while suppressed" {
    var draft: DraftState = .{

test "buildTransportText compacts long draft into progress preview" {
    const long_text = "abcdef" ** 700;
    const compact = try buildTransportText(std.testing.allocator, long_text, 1_000, 16_000);

    try std.testing.expect(std.mem.indexOf(u8, compact, "Latest excerpt:") != null);

test "buildHeartbeatText emits visible progress status" {
    const heartbeat = try buildHeartbeatText(std.testing.allocator, 5_000, 17_500);


test "heartbeatDraft flushes pending visible text after interval" {

        var tmp = flush;


test "heartbeatDraft stays quiet when visible text was already flushed" {


test "heartbeatDraft emits heartbeat when no visible draft is available" {

        var tmp = flush;

