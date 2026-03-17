//! Response cache — avoid burning tokens on repeated prompts.
//!
//! Stores LLM responses in a separate SQLite database keyed by a hash of
//! (model, system_prompt, user_prompt). Entries expire after a configurable
//! TTL. The cache is optional and disabled by default.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const sqlite_mod = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");
const c = sqlite_mod.c;
const SQLITE_STATIC = sqlite_mod.SQLITE_STATIC;

pub const ResponseCache = struct {

// ── Tests ──────────────────────────────────────────────────────────

test "cache key deterministic" {
    const k1 = ResponseCache.cacheKey("gpt-4", "sys", "hello");
    const k2 = ResponseCache.cacheKey("gpt-4", "sys", "hello");

test "cache key varies by model" {
    const k1 = ResponseCache.cacheKey("gpt-4", null, "hello");
    const k2 = ResponseCache.cacheKey("claude-3", null, "hello");

test "cache key varies by system prompt" {
    const k1 = ResponseCache.cacheKey("gpt-4", "You are helpful", "hello");
    const k2 = ResponseCache.cacheKey("gpt-4", "You are rude", "hello");

test "cache key varies by prompt" {
    const k1 = ResponseCache.cacheKey("gpt-4", null, "hello");
    const k2 = ResponseCache.cacheKey("gpt-4", null, "goodbye");

test "cache put and get" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "What is Zig?");


    const result = try cache_inst.get(std.testing.allocator, key_hex);

test "cache miss returns null" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    const result = try cache_inst.get(std.testing.allocator, "nonexistent_key");

test "cache expired entry returns null" {
    var cache_inst = try ResponseCache.init(":memory:", 0, 1000); // 0-minute TTL

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "test");


    const result = try cache_inst.get(std.testing.allocator, key_hex);
    // With TTL=0, cutoff = now, and created_at <= now, so this should be null

test "cache hit count incremented" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "hello");


    // 3 hits
        const r = try cache_inst.get(std.testing.allocator, key_hex);

    const s = try cache_inst.stats();

test "cache tokens saved calculated" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "explain zig");


    // 5 cache hits * 100 tokens = 500 tokens saved
        const r = try cache_inst.get(std.testing.allocator, key_hex);

    const s = try cache_inst.stats();

test "cache lru eviction" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 3); // max 3 entries

        var prompt_buf: [64]u8 = undefined;
        const prompt = std.fmt.bufPrint(&prompt_buf, "prompt{

    const s = try cache_inst.stats();

test "cache clear wipes all" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

        var prompt_buf: [64]u8 = undefined;
        const prompt = std.fmt.bufPrint(&prompt_buf, "prompt{

    const cleared = try cache_inst.clear();

    const s = try cache_inst.stats();

test "cache stats empty" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    const s = try cache_inst.stats();

test "cache overwrite same key" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "question");


    const result = try cache_inst.get(std.testing.allocator, key_hex);

    const s = try cache_inst.stats();

test "cache key hex is 16 chars" {
    var buf: [16]u8 = undefined;
    const hex = ResponseCache.cacheKeyHex(&buf, "gpt-4", null, "hello");

test "cache key includes system prompt in hash" {
    // Keys with different system prompts should differ
    const k1 = ResponseCache.cacheKey("gpt-4", "system A", "hello");
    const k2 = ResponseCache.cacheKey("gpt-4", "system B", "hello");

test "cache key no delimiter collision" {
    // With naive "|" delimiter, these would collide:
    //   model="a" sys="|b"  prompt="c"  -> hash("a||b|c")
    //   model="a" sys=""    prompt="b|c" -> hash("a||b|c")
    // Length-prefixed hashing prevents this.
    const k1 = ResponseCache.cacheKey("a", "|b", "c");
    const k2 = ResponseCache.cacheKey("a", "", "b|c");

    // Also: null sys vs empty sys must differ
    const k3 = ResponseCache.cacheKey("m", null, "p");
    const k4 = ResponseCache.cacheKey("m", "", "p");

test "cache unicode prompt handling" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e\xe3\x81\xae\xe3\x83\x86\xe3\x82\xb9\xe3\x83\x88");


    const result = try cache_inst.get(std.testing.allocator, key_hex);

test "cache put then clear then get returns null" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "test");


    const result = try cache_inst.get(std.testing.allocator, key_hex);

test "cache multiple different keys" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf1: [16]u8 = undefined;
    const key1 = ResponseCache.cacheKeyHex(&key_buf1, "gpt-4", null, "prompt1");

    var key_buf2: [16]u8 = undefined;
    const key2 = ResponseCache.cacheKeyHex(&key_buf2, "gpt-4", null, "prompt2");

    const s = try cache_inst.stats();

    const r1 = try cache_inst.get(std.testing.allocator, key1);

    const r2 = try cache_inst.get(std.testing.allocator, key2);

test "cache stats after multiple puts and hits" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf1: [16]u8 = undefined;
    const key1 = ResponseCache.cacheKeyHex(&key_buf1, "gpt-4", null, "q1");

    var key_buf2: [16]u8 = undefined;
    const key2 = ResponseCache.cacheKeyHex(&key_buf2, "gpt-4", null, "q2");

    // 2 hits on key1, 3 hits on key2
        const r = try cache_inst.get(std.testing.allocator, key1);
        const r = try cache_inst.get(std.testing.allocator, key2);

    const s = try cache_inst.stats();
    // tokens saved: 2*50 + 3*100 = 400

test "cache lru keeps most recently accessed" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 2); // max 2 entries

    var key_buf1: [16]u8 = undefined;
    const key1 = ResponseCache.cacheKeyHex(&key_buf1, "gpt-4", null, "oldest");

    var key_buf2: [16]u8 = undefined;
    const key2 = ResponseCache.cacheKeyHex(&key_buf2, "gpt-4", null, "middle");

    // Access key1 to make it recently used
    const r = try cache_inst.get(std.testing.allocator, key1);

    // Add a third entry, should evict the least recently accessed
    var key_buf3: [16]u8 = undefined;
    const key3 = ResponseCache.cacheKeyHex(&key_buf3, "gpt-4", null, "newest");

    const s = try cache_inst.stats();

test "cache empty response stored" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "empty response test");


    // Empty string stored as empty, get returns null because len == 0
    const result = try cache_inst.get(std.testing.allocator, key_hex);
    // The implementation returns null for len==0, which is expected

test "cache zero token count" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "zero tokens");


    const r = try cache_inst.get(std.testing.allocator, key_hex);

    const s = try cache_inst.stats();

test "cache large max entries" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000000);

    // Just verify it can be created and used with large max_entries
    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "test");

    const s = try cache_inst.stats();

test "cache key with system prompt" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "gpt-4", "You are helpful", "hello");


    const result = try cache_inst.get(std.testing.allocator, key_hex);

test "cache clear returns zero on empty" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    const cleared = try cache_inst.clear();

// ── R3 Tests ──────────────────────────────────────────────────────

test "R3: cache key no delimiter collision — boundary-shifted fields" {
    // These would collide with a naive delimiter approach:
    //   ("a", "|b", "c") vs ("a", "", "b|c")
    // Length-prefixed hashing must distinguish them.
    const k1 = ResponseCache.cacheKey("a", "|b", "c");
    const k2 = ResponseCache.cacheKey("a", "", "b|c");

    // Also verify boundary between model and system_prompt:
    //   ("ab", "c", "d") vs ("a", "bc", "d")
    const k3 = ResponseCache.cacheKey("ab", "c", "d");
    const k4 = ResponseCache.cacheKey("a", "bc", "d");

    // And boundary between system_prompt and user_prompt:
    //   ("m", "ab", "c") vs ("m", "a", "bc")
    const k5 = ResponseCache.cacheKey("m", "ab", "c");
    const k6 = ResponseCache.cacheKey("m", "a", "bc");

test "R3: cache store then retrieve verifies content matches" {
    var cache_inst = try ResponseCache.init(":memory:", 60, 1000);

    const test_response = "This is a detailed response about Zig's comptime features.";
    var key_buf: [16]u8 = undefined;
    const key_hex = ResponseCache.cacheKeyHex(&key_buf, "claude-3", "Be helpful", "Tell me about comptime");


    // Retrieve and verify exact content
    const result = try cache_inst.get(std.testing.allocator, key_hex);

    // Verify a different key misses
    var miss_buf: [16]u8 = undefined;
    const miss_key = ResponseCache.cacheKeyHex(&miss_buf, "claude-3", "Be helpful", "different prompt");
    const miss_result = try cache_inst.get(std.testing.allocator, miss_key);
