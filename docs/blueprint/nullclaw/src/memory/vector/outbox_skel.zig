//! VectorOutbox — durable outbox for vector sync operations.
//!
//! Enqueues upsert/delete operations against the vector store and
//! drains them reliably with retry semantics. Dead letters (items
//! that exceed max_retries) are purged separately.
//!
//! The outbox borrows its SQLite handle from SqliteMemory — it does
//! NOT own the database connection.

const std = @import("std");
const build_options = @import("build_options");
const Allocator = std.mem.Allocator;
const sqlite_mod = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");
const c = sqlite_mod.c;
const SQLITE_STATIC = sqlite_mod.SQLITE_STATIC;
const embeddings = @import("embeddings.zig");
const vector_store_mod = @import("store.zig");
const circuit_breaker_mod = @import("circuit_breaker.zig");
const log = std.log.scoped(.outbox);

pub const VectorOutbox = struct {

// ── Tests ──────────────────────────────────────────────────────────

const testing = std.testing;

const TestSetup = struct {

fn testSetup(allocator: Allocator) !TestSetup

/// Helper: insert a row into the memories table so drain can find content.
fn insertMemory(db: ?*c.sqlite3, key: []const u8, content: []const u8) !void

/// Helper: manually set attempts on an outbox row.
fn setAttempts(db: ?*c.sqlite3, memory_key: []const u8, attempts: i32) !void

/// Helper: get total row count from vector_outbox (regardless of attempts).
fn totalOutboxCount(db: ?*c.sqlite3) !usize

// 1. migrate creates table (no error)
test "migrate creates vector_outbox table" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);
    // If we get here, migrate succeeded — table exists.
    // Verify by inserting directly.
    const cnt = try setup.ob.pendingCount();

// 2. enqueue inserts row (then pendingCount == 1)
test "enqueue inserts row" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    const cnt = try setup.ob.pendingCount();

// 3. enqueue upsert + delete (pendingCount == 2)
test "enqueue upsert and delete" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    const cnt = try setup.ob.pendingCount();

// 4. pendingCount returns correct count
test "pendingCount returns correct count" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);


// 5. drain with noop provider processes items (upsert with content)
test "drain upsert succeeds when content exists in memories" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    // Store content in memories table

    // Enqueue an upsert

    // Drain with noop embedding provider
    var noop = embeddings.NoopEmbedding{

// 6. drain deletes item from outbox when content not found (no content to embed)
test "drain removes upsert when content not found" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    // Enqueue upsert but do NOT store content in memories

    var noop = embeddings.NoopEmbedding{

// 7. drain deletes item from outbox on success
test "drain deletes item from outbox on success" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);


    var noop = embeddings.NoopEmbedding{

// 8. purgeDeadLetters removes over-limit items
test "purgeDeadLetters removes over-limit items" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    // max_retries = 2

    // Set attempts >= max_retries for the dead ones

    const purged = try setup.ob.purgeDeadLetters();

    // Only alive remains

// 9. drain respects max_retries (items at limit are skipped)
test "drain respects max_retries" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    // max_retries = 2 → items with attempts >= 2 should NOT be processed


    var noop = embeddings.NoopEmbedding{

// 10. drain with circuit breaker records success
test "drain with circuit breaker records success" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);


    var noop = embeddings.NoopEmbedding{

// 11. drain with empty outbox returns 0
test "drain with empty outbox returns 0" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    var noop = embeddings.NoopEmbedding{

// 12. multiple enqueue + drain cycle
test "multiple enqueue and drain cycle" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    // First cycle

    var noop = embeddings.NoopEmbedding{

// 13. drain upsert with content verifies vector store receives it
test "drain upsert stores embedding in vector store" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);


    var noop = embeddings.NoopEmbedding{

// 14. drain delete calls vector_store.delete
test "drain delete removes from vector store" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    const vs = setup.vs_impl.store();

    // Pre-populate vector store with a key

    // Enqueue a delete

    var noop = embeddings.NoopEmbedding{

// 15. pendingCount after drain is reduced
test "pendingCount after drain is reduced" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);



    var noop = embeddings.NoopEmbedding{

// ── R3 tests ──────────────────────────────────────────────────────

/// Helper: read the attempts count for a given memory_key from vector_outbox.
fn getAttempts(db: ?*c.sqlite3, memory_key: []const u8) !?i32

/// Failing embedding provider for testing drain failure paths.
const FailingEmbedding = struct {

// R3-1: enqueue → drain → verify items processed and removed
test "enqueue drain verify items processed" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    // Insert 3 items with content


    var noop = embeddings.NoopEmbedding{

// R3-2: enqueue → fail drain → verify retry count incremented
test "drain failure increments retry count" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    // Insert content so drain attempts embedding (which will fail)

    // Use FailingEmbedding that always returns error
    var failing = FailingEmbedding{

// R3-3: dead letter — max retries exceeded → purge removes item
test "dead letter purge removes exhausted items" {
    const allocator = testing.allocator;
    var setup = try testSetup(allocator);

    // Enqueue items and manually exhaust retries

    // Set dead_a and dead_b past max_retries (max_retries=2)

    // alive_c is still at attempts=0 — should survive purge

    const purged = try setup.ob.purgeDeadLetters();

    // Only alive_c remains
