//! Retrieval engine — aggregates candidates from multiple sources,
//! merges via RRF, and returns ranked results.
//!
//! Core types: RetrievalCandidate, RetrievalSourceAdapter (vtable),
//! PrimaryAdapter (wraps Memory.recall), RetrievalEngine.

const std = @import("std");
const build_options = @import("build_options");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryEntry = root.MemoryEntry;
const MemoryCategory = root.MemoryCategory;
const config_types = @import("../../config_types.zig");
const rrf = @import("rrf.zig");
const vector_store_mod = @import("../vector/store.zig");
const circuit_breaker_mod = @import("../vector/circuit_breaker.zig");
const embeddings_mod = @import("../vector/embeddings.zig");
const temporal_decay_mod = @import("temporal_decay.zig");
const mmr_mod = @import("mmr.zig");
const query_expansion_mod = @import("query_expansion.zig");
const adaptive_mod = @import("adaptive.zig");
const llm_reranker_mod = @import("llm_reranker.zig");
const sqlite_mod = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");
const log = std.log.scoped(.retrieval);

// ── Pipeline stage ordering ──────────────────────────────────────

/// Retrieval pipeline stages in execution order.
/// Each stage transforms the candidate list in a deterministic sequence.
pub const RetrievalStage = enum {
    /// Stage 0: Query expansion (stopword filtering, FTS5 optimization)
    /// Stage 1: Keyword search across all sources
    /// Stage 2: Vector/embedding search (if hybrid enabled)
    /// Stage 3: Merge keyword + vector via RRF
    /// Stage 4: Apply minimum relevance threshold
    /// Stage 5: Apply temporal decay to older memories
    /// Stage 6: MMR diversity reranking
    /// Stage 7: LLM reranker (optional, requires callback)
    /// Stage 8: Final limit/truncation

/// The canonical pipeline order. All stages execute in this sequence.

// ── RetrievalCandidate ─────────────────────────────────────────────

pub const RetrievalCandidate = struct {

pub fn freeCandidates(allocator: Allocator, candidates: []RetrievalCandidate) void

/// Convert MemoryEntry slice to RetrievalCandidate slice.
/// Caller owns the returned slice. Entries are NOT freed.
pub fn entriesToCandidates(allocator: Allocator, entries: []const MemoryEntry) ![]RetrievalCandidate

// ── SourceCapabilities ─────────────────────────────────────────────

pub const SourceCapabilities = struct {

// ── RetrievalSourceAdapter vtable ──────────────────────────────────

pub const RetrievalSourceAdapter = struct {

// ── PrimaryAdapter ─────────────────────────────────────────────────

pub const PrimaryAdapter = struct {

// ── RetrievalEngine ────────────────────────────────────────────────

pub const RetrievalEngine = struct {
    // Vector search components (all optional, null = keyword-only)
    // Post-processing stage configs
    // Extended pipeline stages (configured via MemoryRetrievalStagesConfig)
    /// Optional callback for LLM reranking. If set and llm_reranker is enabled,
    /// the engine calls this with a prompt and expects ranked indices in response.
    /// Signature: fn(allocator, prompt) -> response_text or error

/// Filter candidates below min_score threshold.
/// Returns the (possibly shrunk) slice. Filtered entries are deinited.
/// NaN scores are always filtered out regardless of min_score.
fn applyMinRelevance(allocator: Allocator, candidates: []RetrievalCandidate, min_score: f64) []RetrievalCandidate

/// Shrink a candidate slice to `new_len`, maintaining correct allocation metadata.
/// On realloc failure, copies to a fresh allocation rather than returning a
/// sub-slice whose length mismatches the allocation (which violates the allocator
/// contract and causes UB with debug allocators like GPA).
fn shrinkAlloc(allocator: Allocator, slice: []RetrievalCandidate, new_len: usize) []RetrievalCandidate

/// Convert VectorResult slice to RetrievalCandidate slice.
/// Each result gets source="vector", vector_score set, content=key (minimal).
fn vectorResultsToCandidates(allocator: Allocator, vec_results: []const vector_store_mod.VectorResult) ![]RetrievalCandidate

// ── Tests ──────────────────────────────────────────────────────────

const none_mod = @import("../engines/none.zig");

test "RetrievalCandidate deinit frees all fields" {
    const allocator = std.testing.allocator;
    // testing allocator detects leaks

test "RetrievalCandidate deinit frees custom category" {
    const allocator = std.testing.allocator;

test "freeCandidates frees slice" {
    const allocator = std.testing.allocator;
    var candidates = try allocator.alloc(RetrievalCandidate, 1);

test "PrimaryAdapter.name() returns primary" {
    var backend = none_mod.NoneMemory.init();
    var pa = PrimaryAdapter.init(backend.memory());
    const a = pa.adapter();

test "PrimaryAdapter.capabilities() correct" {
    var backend = none_mod.NoneMemory.init();
    var pa = PrimaryAdapter.init(backend.memory());
    const a = pa.adapter();
    const caps = a.getCapabilities();

test "PrimaryAdapter with NoneMemory returns empty" {
    const allocator = std.testing.allocator;
    var backend = none_mod.NoneMemory.init();
    var pa = PrimaryAdapter.init(backend.memory());
    const a = pa.adapter();
    const results = try a.keywordCandidates(allocator, "query", 5, null);

test "PrimaryAdapter healthCheck delegates" {
    var backend = none_mod.NoneMemory.init();
    var pa = PrimaryAdapter.init(backend.memory());
    const a = pa.adapter();

test "PrimaryAdapter.keywordCandidates converts MemoryEntry correctly" {

    const allocator = std.testing.allocator;
    var db = try sqlite_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = db.memory();


    var pa = PrimaryAdapter.init(mem);
    const a = pa.adapter();
    const results = try a.keywordCandidates(allocator, "zig", 10, null);

    // keyword_rank should be 1-based

test "PrimaryAdapter keyword_rank is 1-based sequential" {

    const allocator = std.testing.allocator;
    var db = try sqlite_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = db.memory();


    var pa = PrimaryAdapter.init(mem);
    const a = pa.adapter();
    const results = try a.keywordCandidates(allocator, "searchable", 10, null);


test "RetrievalEngine.init with defaults" {
    const allocator = std.testing.allocator;
    var engine = RetrievalEngine.init(allocator, .{

test "Engine.search with single primary source" {

    const allocator = std.testing.allocator;
    var db = try sqlite_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = db.memory();

    try mem.store("test_key", "test content for search", .core, null);

    var pa = PrimaryAdapter.init(mem);
    var engine = RetrievalEngine.init(allocator, .{

test "Engine.search with empty results returns empty" {
    const allocator = std.testing.allocator;
    var backend = none_mod.NoneMemory.init();

    var pa = PrimaryAdapter.init(backend.memory());
    var engine = RetrievalEngine.init(allocator, .{

test "Engine.search applies min_score filter" {

    const allocator = std.testing.allocator;
    var db = try sqlite_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = db.memory();


    var pa = PrimaryAdapter.init(mem);

    const results = try engine.search(allocator, "searchable", null);
    // All results should be filtered out due to high min_score

test "Engine.search applies top_k truncation" {

    const allocator = std.testing.allocator;
    var db = try sqlite_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = db.memory();

        const key = try std.fmt.allocPrint(allocator, "k{

    var pa = PrimaryAdapter.init(mem);

    const results = try engine.search(allocator, "searchable", null);

test "Engine.deinit cleans up sources" {
    const allocator = std.testing.allocator;
    var backend = none_mod.NoneMemory.init();

    var pa = PrimaryAdapter.init(backend.memory());
    var engine = RetrievalEngine.init(allocator, .{

test "Engine with no sources returns empty" {
    const allocator = std.testing.allocator;
    var engine = RetrievalEngine.init(allocator, .{

test "entriesToCandidates converts correctly" {

    const allocator = std.testing.allocator;
    var db = try sqlite_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = db.memory();

    const entries = try mem.recall(allocator, "test", 5, null);

    const candidates = try entriesToCandidates(allocator, entries);


test "regression anchor: Engine with PrimaryAdapter matches raw recall order" {

    const allocator = std.testing.allocator;
    var db = try sqlite_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = db.memory();


    // Raw recall
    const raw = try mem.recall(allocator, "searchable", 10, null);

    // Engine search
    var pa = PrimaryAdapter.init(mem);
    var engine = RetrievalEngine.init(allocator, .{

test "Engine with hybrid disabled stays keyword-only" {
    const allocator = std.testing.allocator;
    var backend = none_mod.NoneMemory.init();

    var pa = PrimaryAdapter.init(backend.memory());
    var engine = RetrievalEngine.init(allocator, .{

test "Engine.setVectorSearch stores fields" {
    const allocator = std.testing.allocator;
    var noop = embeddings_mod.NoopEmbedding{

test "vectorResultsToCandidates converts correctly" {
    const allocator = std.testing.allocator;
    const key1 = try allocator.dupe(u8, "key_a");
    const key2 = try allocator.dupe(u8, "key_b");


    const candidates = try vectorResultsToCandidates(allocator, &vec_results);


test "Engine with circuit breaker open skips vector search" {
    const allocator = std.testing.allocator;
    var backend = none_mod.NoneMemory.init();

    var pa = PrimaryAdapter.init(backend.memory());
    var engine = RetrievalEngine.init(allocator, .{

test "Engine search with hybrid disabled ignores vector components" {
    const allocator = std.testing.allocator;
    var backend = none_mod.NoneMemory.init();

    var pa = PrimaryAdapter.init(backend.memory());
    var engine = RetrievalEngine.init(allocator, .{

test "pipeline_order has correct stage count" {

test "Engine with temporal decay config" {
    const allocator = std.testing.allocator;


test "Engine with MMR config" {
    const allocator = std.testing.allocator;


test {
