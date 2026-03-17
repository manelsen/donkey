const std = @import("std");
const memory_mod = @import("../memory/root.zig");
const multimodal = @import("../multimodal.zig");
const Memory = memory_mod.Memory;
const MemoryEntry = memory_mod.MemoryEntry;
const MemoryRuntime = memory_mod.MemoryRuntime;

// ═══════════════════════════════════════════════════════════════════════════
// Memory Loader — inject relevant memory context into user messages
// ═══════════════════════════════════════════════════════════════════════════

/// Default number of memory entries to recall per query.
const DEFAULT_RECALL_LIMIT: usize = 5;
const GLOBAL_RECALL_CANDIDATE_LIMIT: usize = 64;

/// Maximum total bytes of memory context injected into a message.
/// Prevents a few large entries from blowing the token budget.
/// ~4000 chars ~ 1000 tokens — a safe ceiling for context injection.
const MAX_CONTEXT_BYTES: usize = 4_000;

/// Truncate a UTF-8 slice to at most `max_len` bytes without splitting
/// a multi-byte sequence. Backs up over trailing continuation bytes (0x80..0xBF).
fn truncateUtf8(s: []const u8, max_len: usize) []const u8

fn containsKey(entries: []const MemoryEntry, key: []const u8) bool

fn isInternalMemoryKey(key: []const u8) bool

fn extractMarkdownMemoryKey(content: []const u8) ?[]const u8

fn isInternalMemoryEntry(entry: MemoryEntry) bool

fn sanitizeMemoryText(allocator: std.mem.Allocator, text: []const u8) ![]const u8

/// Build a memory context preamble by searching stored memories.
///
/// Returns a formatted string like:
/// ```
/// [Memory context]
/// - key1: value1
/// - key2: value2
/// ```
///
/// Returns an empty owned string if no relevant memories are found.

    // When scoped recall is enabled, also include global (session_id = null) memory
    // so long-term facts from memory_store remain visible in session chats.
    var global_entries: ?[]MemoryEntry = null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = buf.writer(allocator);

    var appended: usize = 0;
    var wrote_header = false;

        // Truncate individual entry content to prevent a single large memory from blowing the budget
        const content = truncateUtf8(entry.content, MAX_CONTEXT_BYTES / 2);
        const sanitized = try sanitizeMemoryText(allocator, content);


                const content = truncateUtf8(entry.content, MAX_CONTEXT_BYTES / 2);
                const sanitized = try sanitizeMemoryText(allocator, content);



/// Load context using the full retrieval pipeline (hybrid search, RRF, etc.)
/// when a MemoryRuntime is available.


    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = buf.writer(allocator);
    var wrote_header = false;

        const snippet = truncateUtf8(cand.snippet, MAX_CONTEXT_BYTES / 2);
        const sanitized = try sanitizeMemoryText(allocator, snippet);


/// Enrich a user message with memory context prepended.
/// If no context is available, returns an owned dupe of the original message.
    const context = try loadContext(allocator, mem, user_message, session_id);


/// Enrich a user message using the retrieval engine if available, else raw recall.



// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

test "loadContext returns empty for no-op memory" {
    const allocator = std.testing.allocator;
    var none_mem = memory_mod.NoneMemory.init();
    const mem = none_mem.memory();

    const context = try loadContext(allocator, mem, "hello", null);


test "enrichMessage with no context returns original" {
    const allocator = std.testing.allocator;
    var none_mem = memory_mod.NoneMemory.init();
    const mem = none_mem.memory();

    const enriched = try enrichMessage(allocator, mem, "hello", null);


test "loadContext with session_id includes global entries but not other sessions" {
    const allocator = std.testing.allocator;

    var sqlite_mem = try memory_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    const context = try loadContext(allocator, mem, "favorite", "sess-a");


test "truncateUtf8 does not split multi-byte sequences" {
    // ASCII-only: truncation at limit

    // Under limit: returns as-is

    // 2-byte char at boundary: "aaa" (3 bytes) + "Й" (D0 99 = 2 bytes)
    const s2 = "aaa\xd0\x99";
    // Limit 4: byte 4 is 0x99 (continuation), back up to 3 which is 0xD0 (leading) -> [0..3]
    // Limit 5: full string fits exactly

    // 3-byte char "中" (E4 B8 AD) at boundary
    const s3 = "aa\xe4\xb8\xad";
    // Limit 3: byte 3 is 0xB8 (continuation), back to 2 -> 0xE4 (leading) -> [0..2]
    // Limit 4: byte 4 is 0xAD (continuation), back to 3 -> 0xB8 (continuation), back to 2 -> 0xE4 (leading) -> [0..2]

    // 4-byte emoji U+1F600 (F0 9F 98 80)
    const s4 = "a\xf0\x9f\x98\x80";
    // Limit 2: byte 2 is 0x9F (continuation), back to 1 -> 0xF0 (leading) -> [0..1]

    // All results should be valid UTF-8

test "enrichMessageWithRuntime with no memories returns original message" {
    const allocator = std.testing.allocator;
    var none_mem = memory_mod.NoneMemory.init();
    const mem = none_mem.memory();

    const enriched = try enrichMessageWithRuntime(allocator, mem, null, "hello world", null);


test "enrichMessageWithRuntime with memories prepends context" {
    const allocator = std.testing.allocator;

    var sqlite_mem = try memory_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    const enriched = try enrichMessageWithRuntime(allocator, mem, null, "language", null);

    // Should contain [Memory context] header and the stored entry
    // The original message should appear at the end

test "loadContext filters internal autosave and hygiene entries" {
    const allocator = std.testing.allocator;

    var sqlite_mem = try memory_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    const context = try loadContext(allocator, mem, "русском", null);


test "loadContext filters markdown-encoded internal entries" {
    const allocator = std.testing.allocator;

    var sqlite_mem = try memory_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();

    // Markdown backend serializes memory as "**key**: value".

    const context = try loadContext(allocator, mem, "User", null);


test "loadContext filters bootstrap prompt internal keys" {
    const allocator = std.testing.allocator;

    var sqlite_mem = try memory_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    const context = try loadContext(allocator, mem, "ship", null);


test "loadContextWithRuntime returns empty when only internal entries match" {
    const allocator = std.testing.allocator;

    var sqlite_mem = try memory_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();



    const context = try loadContextWithRuntime(allocator, &rt, "привет", null);
