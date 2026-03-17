const std = @import("std");
const root = @import("root.zig");

pub const TEXT_MESSAGE_DEBOUNCE_SECS: u64 = 3;
pub const LARGE_TEXT_CHAIN_DEBOUNCE_SECS: u64 = 8;
pub const LARGE_TEXT_CHAIN_MIN_PARTS: usize = 4;
pub const LARGE_TEXT_CHAIN_MIN_BYTES: usize = 16 * 1024;
pub const TEXT_SPLIT_LIKELY_MIN_LEN: usize = 500;

pub const PendingTextChainStats = struct {

fn sameSenderAndChat(a: root.ChannelMessage, b: root.ChannelMessage) bool

fn sameChat(a: root.ChannelMessage, b: root.ChannelMessage) bool

fn matchesPendingTextKey(msg: root.ChannelMessage, id: []const u8, sender: []const u8) bool

fn hasMessageId(msg: root.ChannelMessage) bool

fn isLikelySplitTextChunk(msg: root.ChannelMessage) bool

pub fn isSlashCommandMessage(content: []const u8) bool

    const n = @min(pending_messages.len, received_at.len);
    var seen = false;
    var latest: u64 = 0;
    var parts: usize = 0;
    var total_bytes: usize = 0;
        const msg = pending_messages[i];
        if (!seen or received_at[i] > latest) latest = received_at[i];
    return .{ .latest = latest, .parts = parts, .total_bytes = total_bytes };

pub fn textDebounceSecsForChain(parts: usize, total_bytes: usize) u64

fn chainStillWarm(now: u64, stats: PendingTextChainStats) bool

fn chainIsMature(now: u64, stats: PendingTextChainStats) bool


    const n = @min(pending_messages.len, received_at.len);
    var seen = false;
    var next_deadline: u64 = 0;
        const deadline = stats.latest + textDebounceSecsForChain(stats.parts, stats.total_bytes);




    const msg = pending_messages[index];

    var i: usize = 0;
        const pending = pending_messages.items[i];

        const removed = pending_messages.orderedRemove(i);

fn findNextMergeCandidateIndex(messages: []const root.ChannelMessage, start: usize) ?usize

    var merged: std.ArrayListUnmanaged(u8) = .empty;


    const new_content = buildMergedContent(allocator, dst.content, src.content) orelse return false;


    var i: usize = 0;



        var extra = messages.orderedRemove(found_idx);

    const id_dup = try allocator.dupe(u8, id);
    const sender_dup = try allocator.dupe(u8, sender);
    const content_dup = try allocator.dupe(u8, content);


        var tmp = msg;

fn testMessage(id: []const u8, sender: []const u8, content: []const u8, timestamp: u64, message_id: ?i64) root.ChannelMessage

test "telegram ingress mergeConsecutiveMessages handles interleaved chats" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;




test "telegram ingress mergeConsecutiveMessages stops at interleaved sender in same chat" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;




test "telegram ingress mergeConsecutiveMessages skips commands" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;




test "telegram ingress mergeConsecutiveMessages skips whitespace-padded commands" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;




test "telegram ingress mergeConsecutiveMessages chain merges three parts" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;




test "telegram ingress mergeConsecutiveMessages single message no-op" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;




test "telegram ingress shouldDebounceTextMessage handles long chunk and active chain" {
    const alloc = std.testing.allocator;
    var pending_messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;
    var received_at: std.ArrayListUnmanaged(u64) = .empty;

    const now = root.nowEpochSecs();
    const long_content = try alloc.alloc(u8, TEXT_SPLIT_LIKELY_MIN_LEN);

    const long_msg = testMessage("user-a", "chat-a", long_content, now, 1);

    const short_msg = testMessage("user-a", "chat-a", "short", now, 2);



test "telegram ingress shouldDebounceTextMessage does not debounce stale pending chain follow-up" {
    const alloc = std.testing.allocator;
    var pending_messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;
    var received_at: std.ArrayListUnmanaged(u64) = .empty;

    const now = root.nowEpochSecs();
    const short_msg = testMessage("user-a", "chat-a", "oi", now, 77);



test "telegram ingress shouldDebounceTextMessage catches real-world ~3.4k split chunk" {
    const alloc = std.testing.allocator;
    var pending_messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;
    var received_at: std.ArrayListUnmanaged(u64) = .empty;

    const now = root.nowEpochSecs();
    const split_like_content = try alloc.alloc(u8, 3414);

    const msg = testMessage("user-a", "chat-a", split_like_content, now, 100);

test "telegram ingress textDebounceSecsForChain extends window for large chains" {

test "telegram ingress shouldDebounceTextMessage debounces medium chunk (~900 bytes)" {
    const alloc = std.testing.allocator;
    var pending_messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;
    var received_at: std.ArrayListUnmanaged(u64) = .empty;

    const now = root.nowEpochSecs();
    const medium_content = try alloc.alloc(u8, 900);

    const msg = testMessage("user-b", "chat-b", medium_content, now, 101);

test "telegram ingress mergeConsecutiveMessages does not merge short non-consecutive ids" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;




test "telegram ingress mergeConsecutiveMessages merges split-like non-consecutive ids" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;

    const split_like = try alloc.alloc(u8, TEXT_SPLIT_LIKELY_MIN_LEN);




test "telegram ingress mergeConsecutiveMessages allocation failure does not leak" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;

    const large_len = 32 * 1024;
    const large_payload = try alloc.alloc(u8, large_len);


    var failing = std.testing.FailingAllocator.init(alloc, .{

test "telegram ingress cancelPendingTextChainForKey removes only matching sender chat chain" {
    const alloc = std.testing.allocator;
    var pending_messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;
    var received_at: std.ArrayListUnmanaged(u64) = .empty;

    const now = root.nowEpochSecs();



test "telegram ingress nextPendingTextDeadline returns earliest chain deadline" {
    const received_at = [_]u64{
