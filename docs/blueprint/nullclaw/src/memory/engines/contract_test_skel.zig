//! Cross-backend contract tests for the Memory vtable.
//!
//! Every backend that implements Memory must satisfy these invariants.
//! Each test creates its own backend instance, runs the contract, and deinits.

const std = @import("std");
const build_options = @import("build_options");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;

const SqliteMemory = if (build_options.enable_sqlite) @import("sqlite.zig").SqliteMemory else @import("sqlite_disabled.zig").SqliteMemory;
const NoneMemory = @import("none.zig").NoneMemory;
const MarkdownMemory = @import("markdown.zig").MarkdownMemory;
const InMemoryLruMemory = @import("memory_lru.zig").InMemoryLruMemory;

// ── Contract: common invariants ─────────────────────────────────────

/// Validates that a Memory backend satisfies the basic vtable contract:
/// name() returns a non-empty string, healthCheck() is true, and the
/// vtable methods do not crash on an empty store.
fn contractBasics(m: Memory) !void

/// Full CRUD contract for backends that truly persist (sqlite, lucid, postgres).
/// After store(), the entry is retrievable via get(), recall(), list(), count().
/// After forget(), the entry is gone.
fn contractCrud(m: Memory) !void

/// Contract for NoneMemory: every write is a no-op, every read returns empty.
fn contractNone(m: Memory) !void

/// Contract for MarkdownMemory: append-only, forget returns false,
/// content is stored with markdown formatting.
fn contractMarkdown(m: Memory) !void

/// Contract: session_id parameter is accepted by all backends.
fn contractSessionId(m: Memory) !void

// ── SQLite tests ─────────────────────────────────────────────────────

test "contract: sqlite basics" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

test "contract: sqlite crud" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

test "contract: sqlite session_id" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

// ── NoneMemory tests ─────────────────────────────────────────────────

test "contract: none basics" {
    var mem = NoneMemory.init();

test "contract: none noop" {
    var mem = NoneMemory.init();

test "contract: none session_id" {
    var mem = NoneMemory.init();

// ── MarkdownMemory tests ─────────────────────────────────────────────

test "contract: markdown basics" {
    var tmp = std.testing.tmpDir(.{

test "contract: markdown append-only" {
    var tmp = std.testing.tmpDir(.{

test "contract: markdown session_id" {
    var tmp = std.testing.tmpDir(.{

// ── InMemoryLruMemory tests ──────────────────────────────────────────

test "contract: memory_lru basics" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);

test "contract: memory_lru crud" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);

test "contract: memory_lru session_id" {
    var mem = InMemoryLruMemory.init(std.testing.allocator, 100);
