//! PostgreSQL-backed persistent memory via libpq.
//!
//! Compile-time gated behind `build_options.enable_postgres`.
//! When disabled, this file provides only pure-logic helpers and their tests.

const std = @import("std");
const build_options = @import("build_options");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;
const SessionStore = root.SessionStore;


// ── SQL injection protection ──────────────────────────────────────


/// Validate a SQL identifier (schema/table name).
/// Must be 1-63 chars, alphanumeric or underscore only.
pub fn validateIdentifier(name: []const u8) IdentifierError!void

/// Quote a SQL identifier by wrapping in double-quotes.
/// The identifier must have been validated first.
pub fn quoteIdentifier(allocator: std.mem.Allocator, name: []const u8) ![]u8

/// Build a query by substituting {schema} and {table} placeholders.
/// Uses pre-validated, pre-quoted identifiers.
/// Returns a null-terminated slice suitable for passing to libpq C functions.
pub fn buildQuery(allocator: std.mem.Allocator, template: []const u8, schema_q: []const u8, table_q: []const u8) ![:0]u8

fn getNowTimestamp(allocator: std.mem.Allocator) ![]u8

fn generateId(allocator: std.mem.Allocator) ![]u8

// ── PostgresMemory (only available when enable_postgres is true) ──


const PostgresMemoryImpl = struct {
    // Pre-built query templates

// ── Tests ──────────────────────────────────────────────────────────

// Pure logic tests (no PG server needed)

test "validateIdentifier accepts valid names" {

test "validateIdentifier rejects empty" {

test "validateIdentifier rejects too long" {
    const long = "a" ** 64;

test "validateIdentifier rejects special chars" {

test "validateIdentifier accepts max length 63" {
    const ok = "a" ** 63;

test "quoteIdentifier wraps correctly" {
    const result = try quoteIdentifier(std.testing.allocator, "public");

test "quoteIdentifier with underscore" {
    const result = try quoteIdentifier(std.testing.allocator, "my_table");

test "buildQuery replaces schema and table" {

test "buildQuery no placeholders" {
    const result = try buildQuery(std.testing.allocator, "SELECT 1", "\"s\"", "\"t\"");

test "getNowTimestamp returns numeric string" {
    const ts = try getNowTimestamp(std.testing.allocator);

test "generateId produces unique values" {
    const id1 = try generateId(std.testing.allocator);
    const id2 = try generateId(std.testing.allocator);

test "generateId format has dashes" {
    const id = try generateId(std.testing.allocator);

test "buildQuery returns null-terminated string" {
    const result = try buildQuery(std.testing.allocator, "SELECT * FROM{
