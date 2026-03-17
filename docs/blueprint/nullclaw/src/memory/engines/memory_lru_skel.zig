//! In-memory LRU memory backend.
//!
//! Pure in-memory store with LRU eviction — no disk I/O, no external
//! dependencies.  Ideal for testing, CI, and ephemeral sessions.

const std = @import("std");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;

pub const InMemoryLruMemory = struct {

// ── Tests ──────────────────────────────────────────────────────────

test "empty state: get returns null, recall returns empty, count=0" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 10);
    const m = mem.memory();


    const got = try m.get(std.testing.allocator, "nonexistent");

    const recalled = try m.recall(std.testing.allocator, "anything", 10, null);

    const listed = try m.list(std.testing.allocator, null, null);

test "basic store/get/recall/forget cycle" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();

    // Store

    // Get
        const entry = (try m.get(std.testing.allocator, "greeting")).?;

    // Recall via substring
        const results = try m.recall(std.testing.allocator, "hello", 10, null);

    // Forget
    const forgotten = try m.forget("greeting");

    // Forget nonexistent returns false
    const forgotten2 = try m.forget("greeting");

test "update existing key (upsert semantics)" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "key1")).?;

test "LRU eviction: oldest entry evicted at capacity" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 3);
    const m = mem.memory();


    // Adding a 4th should evict "a" (oldest)

    const got_a = try m.get(std.testing.allocator, "a");

    const got_d = (try m.get(std.testing.allocator, "d")).?;

test "eviction order: accessing middle entry protects it" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 3);
    const m = mem.memory();


    // Access "a" — moves it to front, so "b" becomes the LRU candidate.
        const entry = (try m.get(std.testing.allocator, "a")).?;

    // Insert "d", should evict "b" (least recently accessed)

    const got_b = try m.get(std.testing.allocator, "b");

    // "a" is still alive
    const got_a = (try m.get(std.testing.allocator, "a")).?;

test "recall with substring matching" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    // Search for "mode" — matches "dark mode enabled"
        const results = try m.recall(std.testing.allocator, "mode", 10, null);

    // Search for "key" — matches key "api_key"
        const results = try m.recall(std.testing.allocator, "key", 10, null);

    // Search for "e" — matches all three
        const results = try m.recall(std.testing.allocator, "e", 10, null);

test "recall with session_id filter" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    // Filter to sess-A
        const results = try m.recall(std.testing.allocator, "data", 10, "sess-A");

    // No filter — all match
        const results = try m.recall(std.testing.allocator, "data", 10, null);

test "list by category filter" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    // List core only
        const results = try m.list(std.testing.allocator, .core, null);

    // List daily only
        const results = try m.list(std.testing.allocator, .daily, null);

    // List all (no filter)
        const results = try m.list(std.testing.allocator, null, null);

test "count accuracy after store/forget" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


test "session_id accepted on store" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    const recalled = try m.recall(std.testing.allocator, "v", 10, "session-42");

    const listed = try m.list(std.testing.allocator, null, "session-42");

test "recall respects limit" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "data", 2, null);

test "custom category preserved" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();

    const entry = (try m.get(std.testing.allocator, "k")).?;

// ── R3 deep review tests ──────────────────────────────────────────

test "LRU store and get with empty key" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "")).?;

test "LRU store and get with empty content" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();

    const entry = (try m.get(std.testing.allocator, "k")).?;

test "LRU store with special chars in key and content" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();

    const key = "key with \"quotes\" and 'apostrophes' and %wildcards%";
    const content = "line1\nline2\ttab\r\nwindows";

    const entry = (try m.get(std.testing.allocator, key)).?;

test "LRU recall with empty query matches everything" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    // Empty string is substring of everything
    const results = try m.recall(std.testing.allocator, "", 10, null);

test "LRU upsert session_id from null to value" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();

        const entry = (try m.get(std.testing.allocator, "k")).?;

        const entry = (try m.get(std.testing.allocator, "k")).?;

test "LRU upsert session_id from value to null" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "k")).?;

test "LRU list with session_id filter" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    const list_a = try m.list(std.testing.allocator, null, "sess-a");

test "LRU list with category and session_id combined" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    const results = try m.list(std.testing.allocator, .core, "sess-a");

test "LRU recall returns most recently accessed first" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    // Access "a" last, so it should come first in recall results
        const entry = (try m.get(std.testing.allocator, "a")).?;

    const results = try m.recall(std.testing.allocator, "common", 10, null);
    // First result should be "a" (most recently accessed)

test "LRU recall with session_id returns only matching" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "shared", 10, "sess-a");

test "LRU forget nonexistent key returns false" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
    const m = mem.memory();

    const result = try m.forget("nonexistent");

test "LRU get on nonexistent key does not increment access counter" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 3);
    const m = mem.memory();

    // Access counter starts at 0

    const result = try m.get(std.testing.allocator, "nonexistent");

    // Access counter should still be 0 (no entry touched)

test "LRU eviction with capacity 1" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 1);
    const m = mem.memory();



    // "a" should be evicted
    const got_a = try m.get(std.testing.allocator, "a");

    const got_b = (try m.get(std.testing.allocator, "b")).?;
