//! Lucid memory backend — bridges local SQLite to the external `lucid` CLI
//! for cross-project semantic memory sync.
//!
//! Architecture:
//!   - Local SqliteMemory is authoritative for all CRUD operations
//!   - `lucid store` syncs writes to the external lucid-memory service
//!   - `lucid context` augments recall with cross-project results
//!   - On CLI failure, enters a cooldown period and falls back to local-only
//!
//! Mirrors ZeroClaw's `LucidMemory` (src/memory/lucid.rs).

const std = @import("std");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;

pub const LucidMemory = struct {
    /// Timestamp (ms since epoch) after which we retry lucid.
    /// 0 means no cooldown active.

// ── Tests ──────────────────────────────────────────────────────────

test "lucid memory name" {
    const allocator = std.testing.allocator;
    const m = mem.memory();

test "lucid store succeeds when lucid binary missing" {
    const allocator = std.testing.allocator;
    const m = mem.memory();


    const entry = try m.get(allocator, "lang");
    var e = entry.?;

test "lucid recall returns local results when lucid unavailable" {
    const allocator = std.testing.allocator;
    const m = mem.memory();


    const results = try m.recall(allocator, "zig", 5, null);

test "lucid list delegates to local" {
    const allocator = std.testing.allocator;
    const m = mem.memory();


    const all = try m.list(allocator, null, null);

    const core_only = try m.list(allocator, .core, null);

test "lucid forget delegates to local" {
    const allocator = std.testing.allocator;
    const m = mem.memory();

    const forgotten = try m.forget("temp");

    const entry = try m.get(allocator, "temp");

test "lucid count delegates to local" {
    const allocator = std.testing.allocator;
    const m = mem.memory();


test "lucid health check delegates to local" {
    const allocator = std.testing.allocator;
    const m = mem.memory();

test "lucid failure cooldown is set on lucid failure" {
    const allocator = std.testing.allocator;

    // Initial state: no cooldown

    // Attempt recall — lucid binary missing, should set cooldown
    const m = mem.memory();
    const results = try m.recall(allocator, "test", 5, null);

    // After failed lucid attempt, cooldown should be active

test "lucid clearFailure resets cooldown" {
    const allocator = std.testing.allocator;


test "parseLucidContext parses valid output" {
    const allocator = std.testing.allocator;

    const entries = try LucidMemory.parseLucidContext(allocator, raw);


    // Check scores descend

test "parseLucidContext handles empty output" {
    const allocator = std.testing.allocator;
    const entries = try LucidMemory.parseLucidContext(allocator, "");

test "parseLucidContext handles no context block" {
    const allocator = std.testing.allocator;
    const raw = "Some random output without any context block";
    const entries = try LucidMemory.parseLucidContext(allocator, raw);

test "parseLucidContext skips empty content" {
    const allocator = std.testing.allocator;
    const entries = try LucidMemory.parseLucidContext(allocator, raw);

test "toLucidType maps categories correctly" {

test "toMemoryCategory maps labels correctly" {

    const visual = LucidMemory.toMemoryCategory("visual");

test "buildSignature creates lowercased key-content pair" {
    const allocator = std.testing.allocator;
    const sig = try LucidMemory.buildSignature(allocator, "Hello", "World");

test "stripPrefix works correctly" {
    const result = LucidMemory.stripPrefix("- [decision] Use tokens", "- [");

    const no_match = LucidMemory.stripPrefix("hello", "- [");

    const short = LucidMemory.stripPrefix("- ", "- [");

test "lucid recall skips lucid when local hits meet threshold" {
    const allocator = std.testing.allocator;
    const m = mem.memory();


    // Store may have triggered cooldown from failed lucid sync — reset it
    // so we can verify recall itself doesn't set it again.

    const results = try m.recall(allocator, "zig", 5, null);

    // Cooldown should still NOT be set because recall short-circuited
    // (local hits >= threshold), so lucid was never attempted during recall.

test "lucid recall timeout is 500ms" {

test "lucid store accepts session_id" {
    const allocator = std.testing.allocator;
    const m = mem.memory();

    // Store with explicit session_id

    const entry = try m.get(allocator, "sess_key");
    var e = entry.?;

test "lucid recall accepts session_id" {
    const allocator = std.testing.allocator;
    const m = mem.memory();

    // Store with same session_id so it's retrievable by that session

    const results = try m.recall(allocator, "searchable", 5, "session-abc");

test "lucid list accepts session_id" {
    const allocator = std.testing.allocator;
    const m = mem.memory();

    // Store with same session_id so it's listable by that session

    const results = try m.list(allocator, null, "session-abc");

// ── SessionStore vtable tests ─────────────────────────────────────

test "lucid sessionStore returns valid vtable" {
    const allocator = std.testing.allocator;

    const store = mem.sessionStore();

test "lucid sessionStore saveMessage + loadMessages roundtrip" {
    const allocator = std.testing.allocator;

    const store = mem.sessionStore();

    const msgs = try store.loadMessages(allocator, "s1");

