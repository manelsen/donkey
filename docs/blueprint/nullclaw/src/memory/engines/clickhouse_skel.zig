//! ClickHouse-backed persistent memory via HTTP API (port 8123).
//!
//! No C dependency — pure Zig HTTP via std.http.Client.
//! Writes are append-only with server-generated Snowflake ordering keys, and
//! reads collapse to the latest row per logical key via argMax. This keeps
//! ordering independent from client clock skew while ReplacingMergeTree(version)
//! provides eventual on-disk compaction. User data is parameterized via
//! ClickHouse query parameters ({name:Type} syntax).

const std = @import("std");
const build_options = @import("build_options");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;
const SessionStore = root.SessionStore;
const MessageEntry = root.MessageEntry;
const log = std.log.scoped(.clickhouse_memory);

// ── SQL injection protection ──────────────────────────────────────


/// Validate a SQL identifier (database/table name).
/// Must be 1-63 chars, alphanumeric or underscore only.
pub fn validateIdentifier(name: []const u8) IdentifierError!void

/// Quote a SQL identifier by wrapping in backticks (ClickHouse syntax).
pub fn quoteIdentifier(allocator: std.mem.Allocator, name: []const u8) ![]u8

/// Escape a string for safe inclusion in ClickHouse string literals.
/// Escapes ', \, \n, \r, \t, and \0.
pub fn escapeClickHouseString(allocator: std.mem.Allocator, input: []const u8) ![]u8

/// Build the ClickHouse HTTP API base URL from host, port, and TLS setting.
pub fn buildUrl(allocator: std.mem.Allocator, host: []const u8, port: u16, use_https: bool) ![]u8

/// Build a Basic auth header value ("Basic base64(user:password)").
/// Returns null if both user and password are empty.
pub fn buildAuthHeader(allocator: std.mem.Allocator, user: []const u8, password: []const u8) !?[]u8

/// Percent-encode a string for use in URL query parameters.
/// Safe characters (unreserved per RFC 3986) are not encoded.
pub fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8

// ── Timestamp / ID helpers ────────────────────────────────────────

fn getNowTimestamp(allocator: std.mem.Allocator) ![]u8

fn generateId(allocator: std.mem.Allocator) ![]u8

// ── TSV parsing helpers ───────────────────────────────────────────

/// Unescape a ClickHouse TabSeparated field value.
/// Handles \n, \r, \t, \\, \0, \'.
pub fn unescapeClickHouseValue(allocator: std.mem.Allocator, input: []const u8) ![]u8

/// Parse ClickHouse TabSeparated output into rows of columns.
/// Each row is a slice of column values (unescaped).
pub fn parseTsvRows(allocator: std.mem.Allocator, body: []const u8) ![]const []const []const u8

/// Free rows returned by parseTsvRows.
pub fn freeTsvRows(allocator: std.mem.Allocator, rows: []const []const []const u8) void

/// Build a MemoryEntry from a TSV row.
/// Expected columns: [id, key, content, category, timestamp, session_id]
fn buildEntry(allocator: std.mem.Allocator, row: []const []const u8) !MemoryEntry

fn isLoopbackHost(host: []const u8) bool

fn validateTransportSecurity(host: []const u8, use_https: bool) !void

// ── ClickHouseMemory ──────────────────────────────────────────────


const ClickHouseMemoryImpl = struct {

fn buildQuotedSuffixTable(allocator: std.mem.Allocator, base: []const u8, suffix: []const u8) ![]u8

// ── Unit Tests ────────────────────────────────────────────────────

test "validateIdentifier accepts valid names" {

test "validateIdentifier rejects empty" {

test "validateIdentifier rejects too long" {
    const long = "a" ** 64;

test "validateIdentifier accepts max length 63" {
    const ok = "a" ** 63;

test "validateIdentifier rejects special chars" {

test "quoteIdentifier wraps in backticks" {
    const result = try quoteIdentifier(std.testing.allocator, "memories");

test "escapeClickHouseString special chars" {
    const result = try escapeClickHouseString(std.testing.allocator, "it's a\nnew\\line\twith\rtab");

test "escapeClickHouseString null bytes" {
    const input = "hello\x00world";
    const result = try escapeClickHouseString(std.testing.allocator, input);

test "escapeClickHouseString no-op for safe strings" {
    const result = try escapeClickHouseString(std.testing.allocator, "hello world 123");

test "buildUrl http" {
    const result = try buildUrl(std.testing.allocator, "127.0.0.1", 8123, false);

test "buildUrl https" {
    const result = try buildUrl(std.testing.allocator, "clickhouse.internal", 8443, true);

test "buildUrl brackets ipv6 hosts" {
    const result = try buildUrl(std.testing.allocator, "::1", 8123, false);

test "buildAuthHeader returns null for empty credentials" {
    const result = try buildAuthHeader(std.testing.allocator, "", "");

test "buildAuthHeader returns Basic header" {
    const result = try buildAuthHeader(std.testing.allocator, "user", "pass");

test "getNowTimestamp returns numeric string" {
    const ts = try getNowTimestamp(std.testing.allocator);

test "generateId produces unique values" {
    const id1 = try generateId(std.testing.allocator);
    const id2 = try generateId(std.testing.allocator);

test "urlEncode safe chars preserved" {
    const result = try urlEncode(std.testing.allocator, "hello-world_123.test~ok");

test "urlEncode special chars encoded" {
    const result = try urlEncode(std.testing.allocator, "hello world&foo=bar");

test "urlEncode percent sign" {
    const result = try urlEncode(std.testing.allocator, "100%done");

test "unescapeClickHouseValue escaped sequences" {
    const result = try unescapeClickHouseValue(std.testing.allocator, "hello\\nworld\\t\\\\end\\'s\\0x");

test "unescapeClickHouseValue plain text" {
    const result = try unescapeClickHouseValue(std.testing.allocator, "simple text");

test "parseTsvRows empty body" {
    const rows = try parseTsvRows(std.testing.allocator, "");

test "parseTsvRows single row" {
    const rows = try parseTsvRows(std.testing.allocator, "a\tb\tc");

test "parseTsvRows multiple rows" {
    const rows = try parseTsvRows(std.testing.allocator, "a\tb\nc\td\n");

test "validateTransportSecurity allows loopback plaintext" {

test "validateTransportSecurity rejects remote plaintext" {

// ── Integration Tests (gated) ─────────────────────────────────────

const ClickHouseIntegrationConfig = struct {

fn isTruthy(raw: []const u8) bool

fn envOrDefault(allocator: std.mem.Allocator, name: []const u8, default_value: []const u8) ![]u8

fn loadClickHouseIntegrationConfig(allocator: std.mem.Allocator) !?ClickHouseIntegrationConfig

test "integration: clickhouse store and get" {
    const integration_cfg = (try loadClickHouseIntegrationConfig(std.testing.allocator)) orelse return;

    const instance_id = try generateId(std.testing.allocator);


    const m = mem.memory();




test "integration: clickhouse count" {
    const integration_cfg = (try loadClickHouseIntegrationConfig(std.testing.allocator)) orelse return;

    const instance_id = try generateId(std.testing.allocator);


    const m = mem.memory();


    const n = try m.count();

test "integration: clickhouse recall" {
    const integration_cfg = (try loadClickHouseIntegrationConfig(std.testing.allocator)) orelse return;

    const instance_id = try generateId(std.testing.allocator);


    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "brown fox", 10, null);


test "integration: clickhouse forget" {
    const integration_cfg = (try loadClickHouseIntegrationConfig(std.testing.allocator)) orelse return;

    const instance_id = try generateId(std.testing.allocator);


    const m = mem.memory();

    const ok = try m.forget("forget-me");

    const entry = try m.get(std.testing.allocator, "forget-me");

test "integration: clickhouse health check" {
    const integration_cfg = (try loadClickHouseIntegrationConfig(std.testing.allocator)) orelse return;

    const instance_id = try generateId(std.testing.allocator);



test "integration: clickhouse name" {
    const integration_cfg = (try loadClickHouseIntegrationConfig(std.testing.allocator)) orelse return;

    const instance_id = try generateId(std.testing.allocator);


