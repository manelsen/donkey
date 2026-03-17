//! Semantic response cache — extends the exact-match ResponseCache with
//! cosine similarity matching on query embeddings.
//!
//! Algorithm (from reference/memory/bigtech.md B3):
//!   1. Compute embedding of user_prompt
//!   2. Search cached embeddings for cosine_sim > threshold (default: 0.95)
//!   3. If found: return cached response (semantic hit)
//!   4. If not found: exact hash check (existing behavior)
//!   5. On miss: call LLM, cache response + embedding
//!
//! The semantic cache stores query embeddings alongside responses in a
//! separate SQLite table (semantic_cache). It bridges the response cache
//! with the vector/embeddings module.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const vector_math = @import("../vector/math.zig");
const embeddings_mod = @import("../vector/embeddings.zig");
const EmbeddingProvider = embeddings_mod.EmbeddingProvider;

const sqlite_mod = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");
const c = sqlite_mod.c;
const SQLITE_STATIC = sqlite_mod.SQLITE_STATIC;

pub const SemanticCache = struct {

// ── Embedding serialization helpers ────────────────────────────────

/// Serialize f32 slice to JSON array string: "[0.1,0.2,0.3]"
pub fn serializeEmbedding(allocator: std.mem.Allocator, embedding: []const f32) ![]u8

/// Deserialize JSON array string to f32 slice.
pub fn deserializeEmbedding(allocator: std.mem.Allocator, json_text: []const u8) ![]f32

// ── Tests ──────────────────────────────────────────────────────────

test "serializeEmbedding roundtrip" {
    const embedding = [_]f32{

test "serializeEmbedding empty" {
    const empty = [_]f32{

test "deserializeEmbedding invalid json" {
    const result = deserializeEmbedding(std.testing.allocator, "not json");

test "deserializeEmbedding not array" {
    const result = deserializeEmbedding(std.testing.allocator, "\"hello\"");

test "SemanticCache init and deinit" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);

    const s = try cache_inst.stats();

test "SemanticCache put and exact get without embedding" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);


    const result = try cache_inst.get(std.testing.allocator, "abc123", null);

test "SemanticCache miss returns null" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);

    const result = try cache_inst.get(std.testing.allocator, "nonexistent", null);

test "SemanticCache stats tracks entries" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);


    const s = try cache_inst.stats();

test "SemanticCache hit count incremented" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);


        const r = try cache_inst.get(std.testing.allocator, "key1", null);

    const s = try cache_inst.stats();

test "SemanticCache clear" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);


    const cleared = try cache_inst.clear();

    const s = try cache_inst.stats();

test "SemanticCache lru eviction" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 3, 0.95, null);

        var key_buf: [16]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "key_{

    const s = try cache_inst.stats();

test "SemanticCache expired entry returns null" {
    var cache_inst = try SemanticCache.init(":memory:", 0, 1000, 0.95, null);


    const result = try cache_inst.get(std.testing.allocator, "key1", null);

test "SemanticCache tokens saved" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);


        const r = try cache_inst.get(std.testing.allocator, "key1", null);

    const s = try cache_inst.stats();

test "SemanticCache put same key replaces (no duplicates)" {
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);


    // Should have exactly 1 entry, not 3
    const s2 = try cache_inst.stats();

    // Should return the latest
    const result = try cache_inst.get(std.testing.allocator, "dup_key", null);

// ── R3 Tests ──────────────────────────────────────────────────────

test "R3: SemanticCache put same prompt_hash twice produces only 1 row" {
    // Regression: with AUTOINCREMENT id and no dedup, rows accumulated unboundedly.
    // The fix is DELETE before INSERT. Verify it works.
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.95, null);

    // Put same hash 10 times

    const s = try cache_inst.stats();

test "R3: SemanticCache findSemanticMatch returns null below threshold" {
    // Without an embedding provider, semantic match is skipped.
    // Test exact-match path: a miss key should return null.
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.99, null);


    // Query with a different hash and no embedding provider -> no semantic match, no exact match
    const result = try cache_inst.get(std.testing.allocator, "hash_b", "some query");

test "R3: SemanticCache exact match returns best match above threshold" {
    // Exact match always returns similarity 1.0 which is above any threshold
    var cache_inst = try SemanticCache.init(":memory:", 60, 1000, 0.99, null);


    const result = try cache_inst.get(std.testing.allocator, "exact_key", null);
