//! Event Bus — inter-component message bus for nullClaw.
//!
//! Two blocking queues (inbound: channels→agent, outbound: agent→channels)
//! on a ring buffer with Mutex+Condition. Foundation for Session Manager,
//! Message tool, Heartbeat execution, Cron dispatch, USB hotplug.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const outbound = @import("outbound.zig");
const streaming = @import("streaming.zig");
const thread_stacks = @import("thread_stacks.zig");

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

pub const InboundMessage = struct {

pub const OutboundMessage = struct {

// ---------------------------------------------------------------------------
// Helpers — duplicate all strings so producer can free its originals
// ---------------------------------------------------------------------------

    // channel is not duped — must be a literal or long-lived config pointer
    const sid = try allocator.dupe(u8, sender_id);
    const cid = try allocator.dupe(u8, chat_id);
    const ct = try allocator.dupe(u8, content);
    const sk = try allocator.dupe(u8, session_key);


/// Create an InboundMessage with media and metadata.
    // channel is not duped — must be a literal or long-lived config pointer
    const sid = try allocator.dupe(u8, sender_id);
    const cid = try allocator.dupe(u8, chat_id);
    const ct = try allocator.dupe(u8, content);
    const sk = try allocator.dupe(u8, session_key);

    // Dupe media array
        const arr = try allocator.alloc([]const u8, media_src.len);
        var i: usize = 0;


    const md = if (metadata_json) |mj| try allocator.dupe(u8, mj) else null;




    // channel is not duped — must be a literal or long-lived config pointer
    const cid = try allocator.dupe(u8, chat_id);
    const ct = try allocator.dupe(u8, content);




    const cid = try allocator.dupe(u8, chat_id);
    const ct = try allocator.dupe(u8, content);
    const aid = try allocator.dupe(u8, account_id);


    const choice_type = @TypeOf(choices_src);
    const Child = comptime choiceItemType(choice_type);
    comptime {

    const normalized = normalizeChoicesSource(choices_src);

    const duped = try allocator.alloc(outbound.Choice, normalized.len);
    var i: usize = 0;

fn choiceItemType(comptime choice_type: type) type

fn normalizeChoicesSource(choices_src: anytype) []const choiceItemType(@TypeOf(choices_src))

    const cid = try allocator.dupe(u8, chat_id);
    const ct = try allocator.dupe(u8, content);
    const choices = try dupeOutboundChoices(allocator, choices_src);


    const cid = try allocator.dupe(u8, chat_id);
    const ct = try allocator.dupe(u8, content);
    const aid = try allocator.dupe(u8, account_id);
    const choices = try dupeOutboundChoices(allocator, choices_src);


/// Create an OutboundMessage with media attachments.
    // channel is not duped — must be a literal or long-lived config pointer
    const cid = try allocator.dupe(u8, chat_id);
    const ct = try allocator.dupe(u8, content);

        const arr = try allocator.alloc([]const u8, media_src.len);
        var i: usize = 0;


// ---------------------------------------------------------------------------
// BoundedQueue — generic ring buffer with Mutex + Condition
// ---------------------------------------------------------------------------

pub fn BoundedQueue(comptime T: type, comptime capacity: usize) type

// ---------------------------------------------------------------------------
// Bus — top-level structure
// ---------------------------------------------------------------------------

pub const QUEUE_CAPACITY: usize = 100;

pub const Bus = struct {

// ===========================================================================
// Tests
// ===========================================================================

// ---------------------------------------------------------------------------
// 1. Struct tests
// ---------------------------------------------------------------------------

test "InboundMessage.deinit frees all fields" {
    const alloc = testing.allocator;
    var msg = try makeInbound(alloc, "telegram", "user1", "chat42", "hello", "telegram:chat42");

test "OutboundMessage.deinit frees all fields" {
    const alloc = testing.allocator;
    var msg = try makeOutbound(alloc, "discord", "room7", "world");

test "makeInbound produces owned copies of non-channel fields" {
    const alloc = testing.allocator;
    var src_content = try alloc.dupe(u8, "body");

    const msg = try makeInbound(alloc, "webhook", "s", "c", src_content, "webhook:c");

    // Mutate source — message must be unaffected (channel is borrowed, not duped)

test "makeOutbound produces owned copies" {
    const alloc = testing.allocator;
    var src_content = try alloc.dupe(u8, "reply");

    const msg = try makeOutbound(alloc, "telegram", "c1", src_content);


test "makeOutboundWithAccount stores account_id" {
    const alloc = testing.allocator;
    const msg = try makeOutboundWithAccount(alloc, "telegram", "backup", "c1", "reply");

test "makeOutboundChunk marks chunk stage" {
    const alloc = testing.allocator;
    const msg = try makeOutboundChunk(alloc, "web", "c1", "delta");

test "makeOutboundChunkWithAccount marks chunk stage" {
    const alloc = testing.allocator;
    const msg = try makeOutboundChunkWithAccount(alloc, "web", "main", "c1", "delta");

test "makeOutboundWithChoices stores structured choices" {
    const alloc = testing.allocator;
    const msg = try makeOutboundWithChoices(alloc, "telegram", "c1", "reply", &choices);

test "makeOutboundWithAccountChoices stores account_id and choices" {
    const alloc = testing.allocator;
    const msg = try makeOutboundWithAccountChoices(alloc, "telegram", "backup", "c1", "reply", &choices);

// ---------------------------------------------------------------------------
// 2. Queue tests
// ---------------------------------------------------------------------------

test "queue init has zero depth" {
    var q = BoundedQueue(u32, 4).init();

test "queue publish + consume single item" {
    var q = BoundedQueue(u32, 4).init();
    const v = q.consume();

test "queue FIFO order" {
    var q = BoundedQueue(u32, 8).init();

test "queue fill to capacity" {
    var q = BoundedQueue(u32, 4).init();
    // Consume one to make room

test "queue close wakes consumer — returns null" {
    var q = BoundedQueue(u32, 4).init();

        fn run(qp: *BoundedQueue(u32, 4)) void

    const val = q.consume(); // blocks until close

test "queue close returns Closed to producer" {
    var q = BoundedQueue(u32, 2).init();

test "queue depth reflects current length" {
    var q = BoundedQueue(u32, 8).init();

// ---------------------------------------------------------------------------
// 3. Bus integration tests
// ---------------------------------------------------------------------------

test "bus roundtrip inbound" {
    const alloc = testing.allocator;
    var bus = Bus.init();

    const msg = try makeInbound(alloc, "telegram", "user1", "chat1", "hi", "telegram:chat1");

    var got = bus.consumeInbound().?;

test "bus roundtrip outbound" {
    const alloc = testing.allocator;
    var bus = Bus.init();

    const msg = try makeOutbound(alloc, "discord", "room1", "pong");

    var got = bus.consumeOutbound().?;

test "bus close stops both queues" {
    var bus = Bus.init();

    const alloc = testing.allocator;
    const in_msg = try makeInbound(alloc, "x", "x", "x", "x", "x:x");

    const out_msg = try makeOutbound(alloc, "x", "x", "x");

test "bus close is idempotent" {
    var bus = Bus.init();
    // No crash — idempotent

test "bus multiple inbound producers" {
    const alloc = testing.allocator;
    var bus = Bus.init();

    const num_threads = 5;
    const msgs_per_thread = 10;

    var handles: [num_threads]std.Thread = undefined;
            fn run(b: *Bus, tid: usize, a: Allocator) void

    var count: usize = 0;
    // Consumer: drain until we have all messages


// ---------------------------------------------------------------------------
// 4. Stress test
// ---------------------------------------------------------------------------

test "bus stress: 10 producers × 100 messages" {
    const alloc = testing.allocator;
    var bus = Bus.init();

    const num_threads = 10;
    const msgs_per_thread = 100;
    const total = num_threads * msgs_per_thread;

    var producers: [num_threads]std.Thread = undefined;
            fn run(b: *Bus, tid: usize, a: Allocator) void

    var count: usize = 0;
        fn run(b: *Bus, cnt: *usize, a: Allocator) void



// ---------------------------------------------------------------------------
// Extra edge-case tests
// ---------------------------------------------------------------------------

test "queue wraparound ring buffer" {
    var q = BoundedQueue(u32, 4).init();
    // Fill and drain twice to exercise wraparound

test "queue consume drains remaining after close" {
    var q = BoundedQueue(u32, 8).init();
    // Should still be able to drain existing items
    // Then null

test "queue publish after close always errors" {
    var q = BoundedQueue(u32, 4).init();

test "bus inbound and outbound are independent" {
    const alloc = testing.allocator;
    var bus = Bus.init();

    const in_msg = try makeInbound(alloc, "ch", "s", "c", "in", "ch:c");

    const out_msg = try makeOutbound(alloc, "ch", "c", "out");


    var got_in = bus.consumeInbound().?;

    var got_out = bus.consumeOutbound().?;

// ---------------------------------------------------------------------------
// 5. Media + Metadata tests
// ---------------------------------------------------------------------------

test "InboundMessage with media and metadata" {
    const alloc = testing.allocator;
    const media_src = [_][]const u8{

test "InboundMessage without media defaults to empty" {
    const alloc = testing.allocator;
    var msg = try makeInbound(alloc, "ch", "s", "c", "hi", "ch:c");

test "OutboundMessage with media" {
    const alloc = testing.allocator;
    const media_src = [_][]const u8{

test "OutboundMessage without media defaults to empty" {
    const alloc = testing.allocator;
    var msg = try makeOutbound(alloc, "ch", "c", "hi");

test "makeInboundFull with null metadata" {
    const alloc = testing.allocator;
    var msg = try makeInboundFull(alloc, "ch", "s", "c", "hi", "ch:c", &.{

test "makeInboundFull media is owned copy" {
    const alloc = testing.allocator;
    var src = try alloc.dupe(u8, "/tmp/test.jpg");
    const media_src = [_][]const u8{

test "bus outbound multiple producers" {
    const alloc = testing.allocator;
    var bus = Bus.init();

    const num_threads = 5;
    const msgs_per_thread = 10;

    var handles: [num_threads]std.Thread = undefined;
            fn run(b: *Bus, tid: usize, a: Allocator) void

    var count: usize = 0;

