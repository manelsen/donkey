//! VectorStore — vtable interface + SQLite shared implementation.
//!
//! Provides a generic vector store abstraction for embedding-based
//! similarity search, plus a concrete SQLite implementation that
//! shares the database handle with SqliteMemory (memory_embeddings table).

const std = @import("std");
const build_options = @import("build_options");
const Allocator = std.mem.Allocator;
const vector = @import("math.zig");
const sqlite_mod = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");
const c = sqlite_mod.c;
const SQLITE_STATIC = sqlite_mod.SQLITE_STATIC;

// ── Health status ─────────────────────────────────────────────────

pub const HealthStatus = struct {

// ── Result types ──────────────────────────────────────────────────

pub const VectorResult = struct {

pub fn freeVectorResults(allocator: Allocator, results: []VectorResult) void

const ANN_SIGNATURE_BITS: u32 = 64;
const ANN_BAND_BITS: u32 = 16;
const ANN_BAND_COUNT: u32 = ANN_SIGNATURE_BITS / ANN_BAND_BITS;
const ANN_DEFAULT_CANDIDATE_MULTIPLIER: u32 = 12;
const ANN_DEFAULT_MIN_CANDIDATES: u32 = 64;

fn queryNorm(query_embedding: []const f32) f64

fn cosineSimilarityBlob(query_embedding: []const f32, query_norm: f64, blob: []const u8) f32

fn indexOfLowestScore(results: []const VectorResult) usize


        const owned_key = try alloc.dupe(u8, key);



    const owned_key = try alloc.dupe(u8, key);




    const query_norm = queryNorm(query_embedding);
    const sql = "SELECT memory_key, embedding FROM memory_embeddings";
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(db, sql, -1, &stmt, null);

    var candidates: std.ArrayListUnmanaged(VectorResult) = .empty;

    var lowest_idx: usize = 0;
    var lowest_score: f32 = 0.0;

            const key_ptr = c.sqlite3_column_text(stmt, 0);
            const key_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 0));

            const blob_ptr: ?[*]const u8 = @ptrCast(c.sqlite3_column_blob(stmt, 1));
            const blob_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 1));

            const score = cosineSimilarityBlob(query_embedding, query_norm, blob_ptr.?[0..blob_len]);
            const key_slice: []const u8 = key_ptr[0..key_len];


        fn lessThan(_: void, a: VectorResult, b: VectorResult) bool

    const result = try alloc.dupe(VectorResult, candidates.items);

fn annCandidateLimit(limit: u32, candidate_multiplier: u32, min_candidates: u32) u32

fn clampU32ToSqliteInt(value: u32) c_int

fn mix64(x_raw: u64) u64

fn projectionCoeff(bit_idx: u32, dim_idx: usize) f64

fn simhashSignatureFromEmbedding(embedding: []const f32) u64

fn simhashSignatureFromBlob(blob: []const u8) u64

fn signatureBands(sig: u64) [ANN_BAND_COUNT]u16

// ── VectorStore vtable ────────────────────────────────────────────

pub const VectorStore = struct {

// ── SqliteSharedVectorStore ───────────────────────────────────────

pub const SqliteSharedVectorStore = struct {

// ── Sidecar vector store ──────────────────────────────────────────
//
// Opens its OWN SQLite database for vector storage.  Use this when the
// primary backend is *not* SQLite-based (markdown, postgres, redis, etc.).
// The sidecar owns the db handle and closes it on deinit.

pub const SqliteSidecarVectorStore = struct {

// ── Sqlite ANN vector store (experimental) ────────────────────────
//
// Uses a lightweight SimHash+band prefilter in SQLite to cut the search
// candidate set, then computes exact cosine on candidates. Falls back to
// exact search when ANN candidate recall is insufficient.

pub const SqliteAnnVectorStore = struct {

// ── Tests ─────────────────────────────────────────────────────────

fn testExecSql(db: ?*c.sqlite3, sql: [:0]const u8) !void

fn testQuerySingleText(allocator: Allocator, db: ?*c.sqlite3, sql: [:0]const u8) ![]u8

test "init with in-memory sqlite" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const cnt = try s.count();

test "upsert stores embedding then verify with count" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const emb = [_]f32{

test "upsert overwrites existing key" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const emb1 = [_]f32{

test "search returns sorted results" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();

    // Insert 3 items: a is very similar to query, b is less similar, c is orthogonal
    const query = [_]f32{

test "search with no data returns empty" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const query = [_]f32{

test "search respects limit" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();

    // Insert 5 items
    var bufs: [5][8]u8 = undefined;
        const key = std.fmt.bufPrint(&bufs[i], "key_{

    const results = try s.search(std.testing.allocator, &[_]f32{

test "delete removes embedding" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const emb = [_]f32{

test "delete non-existent key is no-op" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    // Should not error

test "count returns correct count" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();




test "VectorResult deinit frees key" {
    const allocator = std.testing.allocator;
    const key = try allocator.dupe(u8, "test_key");
    const r = VectorResult{

test "freeVectorResults frees slice" {
    const allocator = std.testing.allocator;
    var results = try allocator.alloc(VectorResult, 2);
    // No leak = pass

test "cosine similarity cross-check: exact match returns score near 1.0" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const emb = [_]f32{

test "blob cosine similarity matches math cosine similarity" {
    const emb = [_]f32{

test "search with zero limit returns empty" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);
    const s = vs.store();

    const results = try s.search(std.testing.allocator, &[_]f32{

test "ann candidate limit respects multiplier and minimum" {

test "sqlite bind int clamp handles u32 overflow safely" {
    const max_sqlite_int: c_int = std.math.maxInt(c_int);

test "projection coeff handles large dimension indices without overflow" {
        const coeff = projectionCoeff(63, dim_idx);

test "sqlite ann search falls back to exact when ann index has no candidates" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var shared = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);
    const shared_store = shared.store();

    var ann = try SqliteAnnVectorStore.init(std.testing.allocator, mem.db, 8, 64);

    // Simulate missing ANN coverage for existing rows.
    var clear_stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(mem.db, "DELETE FROM memory_embedding_ann", -1, &clear_stmt, null);

    const ann_store = ann.store();
    const results = try ann_store.search(std.testing.allocator, &[_]f32{

test "sqlite ann upsert and search basic path" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var ann = try SqliteAnnVectorStore.init(std.testing.allocator, mem.db, 8, 32);

    const s = ann.store();

    const results = try s.search(std.testing.allocator, &[_]f32{

test "sqlite ann backfill refreshes stale rows even when counts match" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var shared = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    var ann = try SqliteAnnVectorStore.init(std.testing.allocator, mem.db, 8, 64);



test "sqlite ann upsert is atomic across embeddings and ann rows" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var ann = try SqliteAnnVectorStore.init(std.testing.allocator, mem.db, 8, 64);


    const s = ann.store();
    var saw_error = false;


test "sqlite ann delete is atomic across embeddings and ann rows" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var ann = try SqliteAnnVectorStore.init(std.testing.allocator, mem.db, 8, 64);

    const s = ann.store();


    var saw_error = false;


test "sqlite ann backfill ignores non-indexable embeddings in stale detection" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var shared = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    var ann = try SqliteAnnVectorStore.init(std.testing.allocator, mem.db, 8, 64);



    const updated_at = try testQuerySingleText(std.testing.allocator, mem.db, "SELECT updated_at FROM memory_embedding_ann WHERE memory_key = 'good'");

test "sqlite ann upsert with empty embedding keeps ann table clean" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var ann = try SqliteAnnVectorStore.init(std.testing.allocator, mem.db, 8, 64);

    const s = ann.store();

test "round-trip: upsert then search finds the key" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const emb = [_]f32{

test "multiple upserts + search returns best match" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();

    // Insert several items

    // Search for something close to "north"
    const query = [_]f32{

test "empty embedding handled gracefully" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const empty: []const f32 = &.{

test "healthCheck returns ok with entry count" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();

    // Insert some data

    const status = try s.healthCheck(std.testing.allocator);


test "healthCheck on empty store returns ok with zero count" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const status = try s.healthCheck(std.testing.allocator);


test "HealthStatus deinit frees error_msg" {
    const allocator = std.testing.allocator;
    const msg = try allocator.dupe(u8, "test error");
    // No leak = pass (testing allocator detects leaks)

test "HealthStatus deinit with null error_msg is safe" {

// ── R3 tests ──────────────────────────────────────────────────────

test "upsert same key updates embedding not duplicate" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();
    const emb1 = [_]f32{

test "search returns results sorted by similarity descending" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();

    // Insert vectors with known similarity to query [1,0,0]

    const query = [_]f32{

test "delete then search returns empty for deleted key" {
    var mem = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");

    var vs = SqliteSharedVectorStore.init(std.testing.allocator, mem.db);

    const s = vs.store();

    const emb = [_]f32{
