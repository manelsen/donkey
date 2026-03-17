//! Embedding providers — convert text to vectors for semantic search.
//!
//! Mirrors ZeroClaw's embeddings module:
//!   - EmbeddingProvider vtable interface
//!   - NoopEmbedding (returns empty/zero vectors, keyword-only fallback)
//!   - OpenAiEmbedding (HTTP POST to /v1/embeddings)
//!   - Factory function: createEmbeddingProvider()

const std = @import("std");
const build_options = @import("build_options");
const appendJsonEscaped = @import("../../util.zig").appendJsonEscaped;
const GeminiEmbedding = @import("embeddings_gemini.zig").GeminiEmbedding;
const VoyageEmbedding = @import("embeddings_voyage.zig").VoyageEmbedding;
const OllamaEmbedding = @import("embeddings_ollama.zig").OllamaEmbedding;
const net_security = @import("../../net_security.zig");

// ── Embedding provider vtable ─────────────────────────────────────

pub const EmbeddingProvider = struct {

// ── Noop provider (keyword-only fallback) ─────────────────────────

pub const NoopEmbedding = struct {
    /// Allocator used to free the heap allocation in deinit.
    /// Set to null only when the instance is stack-allocated by the caller.

// ── OpenAI-compatible embedding provider ──────────────────────────

pub const OpenAiEmbedding = struct {

// ── Helpers ───────────────────────────────────────────────────────

fn hasExplicitApiPath(url: []const u8) bool

/// Require a parseable HTTP(S) endpoint. Plain HTTP is only allowed on local hosts.
fn validateEmbeddingBaseUrl(url: []const u8) !void

/// Parse an OpenAI-compatible embeddings API response to extract the embedding vector.
fn parseEmbeddingResponse(allocator: std.mem.Allocator, json_bytes: []const u8) ![]f32

// ── Embedding cache ───────────────────────────────────────────────

const sqlite_mod = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");
const SqliteMemory = sqlite_mod.SqliteMemory;
const c = sqlite_mod.c;
const SQLITE_STATIC = sqlite_mod.SQLITE_STATIC;

/// Compute a content hash for embedding cache lookups.
/// SHA-256 the content, take first 8 bytes, format as 16 hex characters.
///
/// IMPORTANT: For cache correctness, callers should use `contentHashWithModel`
/// instead, which includes the model name in the hash. Using this function
/// alone risks returning stale embeddings if the embedding model changes.
pub fn contentHash(content: []const u8) [16]u8

/// Compute a content hash that includes the model name.
/// This prevents returning stale cached embeddings when the model changes.
pub fn contentHashWithModel(content: []const u8, model: []const u8) [16]u8

/// Cache an embedding vector for a content hash.
/// Serializes the f32 slice as a JSON array and stores it in embedding_cache.
pub fn cacheEmbedding(db: *SqliteMemory, content_hash: []const u8, embedding: []const f32) !void

/// Retrieve a cached embedding by content hash.
/// Returns null if not found. Caller owns the returned slice.
pub fn getCachedEmbedding(db: *SqliteMemory, content_hash: []const u8, allocator: std.mem.Allocator) !?[]f32

/// Prune the embedding cache, keeping only the newest `max_entries` entries.
/// Returns the number of entries deleted.
pub fn pruneEmbeddingCache(db: *SqliteMemory, max_entries: u32) !u32

// ── Factory ───────────────────────────────────────────────────────

/// Create an embedding provider by name.
/// Returns a NoopEmbedding for unknown providers.




        const base_url = provider_name[7..];

    // Default: noop (keyword-only search) — heap-allocate so the vtable pointer stays valid.
    const noop_inst = try allocator.create(NoopEmbedding);

// ── Tests ─────────────────────────────────────────────────────────

test "hasExplicitApiPath" {

test "parseEmbeddingResponse valid" {
    const result = try parseEmbeddingResponse(std.testing.allocator, json);


test "parseEmbeddingResponse empty data" {
    const result = parseEmbeddingResponse(std.testing.allocator, json);

test "parseEmbeddingResponse missing data" {
    const result = parseEmbeddingResponse(std.testing.allocator, json);

test "parseEmbeddingResponse integer values" {
    const result = try parseEmbeddingResponse(std.testing.allocator, json);

test "OpenAiEmbedding init and deinit" {
    const p = impl_.provider();

test "OpenAiEmbedding init rejects insecure remote http url" {

test "OpenAiEmbedding init accepts localhost http url" {
    const p = impl_.provider();

test "OpenAiEmbedding embeddingsUrl standard" {

    const url = try impl_.embeddingsUrl(std.testing.allocator);

test "OpenAiEmbedding embeddingsUrl with v1 path" {

    const url = try impl_.embeddingsUrl(std.testing.allocator);

test "OpenAiEmbedding embeddingsUrl already has embeddings" {

    const url = try impl_.embeddingsUrl(std.testing.allocator);

// Regression test: createEmbeddingProvider("none") must heap-allocate NoopEmbedding
// so the returned EmbeddingProvider vtable pointer remains valid after the factory returns.
test "createEmbeddingProvider noop is heap allocated and deinit frees memory" {
    const p = try createEmbeddingProvider(std.testing.allocator, "none", null, "", 0);
    // Use the provider — pointer must still be valid here (no dangling ptr).
    const vec = try p.embed(std.testing.allocator, "hello");
    // deinit must free the heap allocation without crashing (verified by allocator leak check).

test "createEmbeddingProvider openai is heap allocated and deinit frees memory" {
    const p = try createEmbeddingProvider(std.testing.allocator, "openai", "test-key", "text-embedding-3-small", 1536);
    // deinit must free all allocations without crashing.

test "createEmbeddingProvider gemini" {
    const p = try createEmbeddingProvider(std.testing.allocator, "gemini", "test-key", "", 0);

test "createEmbeddingProvider gemini with custom model" {
    const p = try createEmbeddingProvider(std.testing.allocator, "gemini", "test-key", "gemini-embedding-001", 1024);

test "createEmbeddingProvider voyage" {
    const p = try createEmbeddingProvider(std.testing.allocator, "voyage", "test-key", "", 0);

test "createEmbeddingProvider voyage with custom model" {
    const p = try createEmbeddingProvider(std.testing.allocator, "voyage", "test-key", "voyage-3", 1024);

test "createEmbeddingProvider ollama" {
    const p = try createEmbeddingProvider(std.testing.allocator, "ollama", null, "", 0);

test "createEmbeddingProvider ollama with custom model" {
    const p = try createEmbeddingProvider(std.testing.allocator, "ollama", null, "mxbai-embed-large", 1024);

test "createEmbeddingProvider custom rejects insecure remote http url" {

// ── Embedding cache tests ─────────────────────────────────────────

test "contentHash produces 16 hex chars" {
    const hash = contentHash("hello world");
    // Verify all characters are hex

test "contentHash is deterministic" {
    const h1 = contentHash("test content");
    const h2 = contentHash("test content");

test "contentHash differs for different inputs" {
    const h1 = contentHash("alpha");
    const h2 = contentHash("beta");

test "contentHashWithModel differs by model" {
    const h1 = contentHashWithModel("same text", "text-embedding-3-small");
    const h2 = contentHashWithModel("same text", "text-embedding-3-large");

test "contentHashWithModel same model same content is deterministic" {
    const h1 = contentHashWithModel("hello", "model-a");
    const h2 = contentHashWithModel("hello", "model-a");

test "contentHashWithModel differs from contentHash" {
    const h1 = contentHash("hello");
    const h2 = contentHashWithModel("hello", "");
    // Even with empty model, the null separator makes them differ

test "cacheEmbedding and getCachedEmbedding roundtrip" {
    var mem = SqliteMemory.init(std.testing.allocator, ":memory:") catch return;

    const embedding = [_]f32{

test "getCachedEmbedding returns null for missing hash" {
    var mem = SqliteMemory.init(std.testing.allocator, ":memory:") catch return;

    const cached = try getCachedEmbedding(&mem, "nonexistent_hash", std.testing.allocator);

test "cacheEmbedding overwrites existing entry" {
    var mem = SqliteMemory.init(std.testing.allocator, ":memory:") catch return;

    const hash = contentHash("overwrite test");
    const emb1 = [_]f32{

test "pruneEmbeddingCache deletes oldest entries" {
    var mem = SqliteMemory.init(std.testing.allocator, ":memory:") catch return;

    // Insert 5 entries with distinct hashes
        var content_buf: [32]u8 = undefined;
        const content = std.fmt.bufPrint(&content_buf, "content_{

    // Prune to keep only 3
    const deleted = try pruneEmbeddingCache(&mem, 3);

    // Verify count is now 3
    const count_sql = "SELECT COUNT(*) FROM embedding_cache";
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(mem.db, count_sql, -1, &stmt, null);

test "pruneEmbeddingCache returns 0 when under limit" {
    var mem = SqliteMemory.init(std.testing.allocator, ":memory:") catch return;

    const hash = contentHash("only one");
    const emb = [_]f32{

test "cacheEmbedding empty vector" {
    var mem = SqliteMemory.init(std.testing.allocator, ":memory:") catch return;

    const hash = contentHash("empty vec");
    const emb = [_]f32{

// ── R3 regression tests ───────────────────────────────────────────

test "parseEmbeddingResponse valid extracts correct f32 array" {
    const result = try parseEmbeddingResponse(std.testing.allocator, json);


test "parseEmbeddingResponse root is array not object returns error" {
    const result = parseEmbeddingResponse(std.testing.allocator, json);

test "parseEmbeddingResponse string value in embedding returns error not silent 0" {
    const result = parseEmbeddingResponse(std.testing.allocator, json);

test "parseEmbeddingResponse null value in embedding returns error" {
    const result = parseEmbeddingResponse(std.testing.allocator, json);

test "parseEmbeddingResponse bool value in embedding returns error" {
    const result = parseEmbeddingResponse(std.testing.allocator, json);

test "contentHashWithModel different models same text produce different hashes" {
    const h1 = contentHashWithModel("identical text", "model-alpha");
    const h2 = contentHashWithModel("identical text", "model-beta");

test "contentHashWithModel same model different text produce different hashes" {
    const h1 = contentHashWithModel("text one", "model-x");
    const h2 = contentHashWithModel("text two", "model-x");
