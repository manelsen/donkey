//! Brain.db source reader — reads SQLite-based memory from OpenClaw/ZeroClaw.
//!
//! Detects schema dynamically via PRAGMA table_info to support both legacy
//! and current brain.db variants. Used by migration.zig for SQLite import.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const sqlite = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");
const c = sqlite.c;

pub const SqliteSourceEntry = struct {


/// Read all entries from a brain.db file. Caller owns returned slice.

    var db: ?*c.sqlite3 = null;
    var rc = c.sqlite3_open_v2(db_path, &db, c.SQLITE_OPEN_READONLY, null);

    // Check memories table exists

    // Detect columns
    const cols = detectColumns(db.?) orelse return error.QueryFailed;

    // Build and execute query
    var query_buf: [256]u8 = undefined;

    var stmt: ?*c.sqlite3_stmt = null;

    var entries: std.ArrayList(SqliteSourceEntry) = .empty;

        const raw_key = columnText(stmt, 0);
        const raw_content = columnText(stmt, 1);
        const raw_category = columnText(stmt, 2);


        const key = allocator.dupe(u8, raw_key) catch return error.OutOfMemory;
        const content = allocator.dupe(u8, raw_content) catch return error.OutOfMemory;
        const category = allocator.dupe(u8, raw_category) catch return error.OutOfMemory;



/// Free all entries returned by readBrainDb.
pub fn freeSqliteEntries(allocator: std.mem.Allocator, entries: []SqliteSourceEntry) void

// ── Internal helpers ───────────────────────────────────────────────

const ColumnMapping = struct {

fn detectColumns(db: *c.sqlite3) ?ColumnMapping

fn tableExists(db: *c.sqlite3, table_name: []const u8) bool

fn columnText(stmt: ?*c.sqlite3_stmt, col: c_int) []const u8

// ── Helper: create in-memory db with schema ────────────────────────

fn createTestDb(allocator: std.mem.Allocator, schema: []const u8) !*c.sqlite3

fn closeTestDb(db: *c.sqlite3) void

fn execSql(db: *c.sqlite3, sql: [*:0]const u8) void

// ── Tests ──────────────────────────────────────────────────────────

test "readBrainDb with standard schema (key/content/category)" {

    // readBrainDb expects a file path; we need to use the in-memory db directly.
    // Since readBrainDb opens its own db, we test via the internal helpers instead.
    // For the full path test, we verify the column detection works.
    const cols = detectColumns(db).?;

test "readBrainDb with legacy schema (id/value/kind)" {

    const cols = detectColumns(db).?;

test "readBrainDb with minimal schema (content only, others fallback)" {

    const cols = detectColumns(db).?;

test "readBrainDb with missing memories table" {

    const result = readBrainDb(std.testing.allocator, ":memory:");

test "readBrainDb with empty table" {

    const cols = detectColumns(db).?;

test "readBrainDb with no content column" {

    const cols = detectColumns(db);

test "column detection: finds key before id before name" {
    // DB with both key and id — key should win
    const cols1 = detectColumns(db1).?;

    // DB with id and name — id should win
    const cols2 = detectColumns(db2).?;

test "column detection: finds content before value" {
    const cols = detectColumns(db).?;

test "freeSqliteEntries frees all allocations" {
    const allocator = std.testing.allocator;
    var entries = try allocator.alloc(SqliteSourceEntry, 2);
    // testing allocator detects leaks

test "multiple entries roundtrip via column detection" {

    const cols = detectColumns(db).?;

    // Query manually to verify entries are readable
    var stmt: ?*c.sqlite3_stmt = null;
    const sql = "SELECT key, content, category FROM memories";

    var count: usize = 0;

test "unicode content preservation" {

    // Insert unicode content via parameterized query
    const insert_sql = "INSERT INTO memories VALUES (?, ?, ?)";
    var insert_stmt: ?*c.sqlite3_stmt = null;

    const unicode_content = "Привет, мир! 🌍 日本語";

    // Read back
    const select_sql = "SELECT content FROM memories WHERE key='unicode_key'";
    var sel_stmt: ?*c.sqlite3_stmt = null;

    const read_back = columnText(sel_stmt, 0);

test "category fallback to core" {
    const cols = detectColumns(db).?;

test "tableExists returns false for non-existent table" {

test "text column detection" {
    const cols = detectColumns(db).?;

test "memory column detection" {
    const cols = detectColumns(db).?;

// ── P5.1: Edge case tests ─────────────────────────────────────────

test "readBrainDb with corrupt file returns no memories table" {

    var tmp = std.testing.tmpDir(.{

test "readBrainDb with empty table returns empty slice" {

    // Create a temp file with an empty memories table
    var tmp = std.testing.tmpDir(.{

test "readBrainDb skips rows with empty content" {

    var tmp = std.testing.tmpDir(.{

test "readBrainDb full roundtrip with file-based db" {

    var tmp = std.testing.tmpDir(.{

test "columnText returns empty for null column" {

    var stmt: ?*c.sqlite3_stmt = null;
    const sql = "SELECT a FROM t";

    const val = columnText(stmt, 0);
