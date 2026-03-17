//! Memory snapshot — export/import core memories as JSON.
//!
//! Mirrors ZeroClaw's snapshot module:
//!   - export_snapshot: dumps all Memory entries to a JSON file
//!   - hydrate_from_snapshot: restores entries from JSON
//!   - should_hydrate: checks if memory is empty but snapshot exists

const std = @import("std");
const build_options = @import("build_options");
const fs_compat = @import("../../fs_compat.zig");
const root = @import("../root.zig");
const json_util = @import("../../json_util.zig");
const Memory = root.Memory;
const MemoryEntry = root.MemoryEntry;
const MemoryCategory = root.MemoryCategory;
const sqlite_mod = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");

/// Default snapshot filename.
pub const SNAPSHOT_FILENAME = "MEMORY_SNAPSHOT.json";

// ── Export ─────────────────────────────────────────────────────────

/// Export all core memories to a JSON snapshot file.
/// Returns the number of entries exported.
pub fn exportSnapshot(allocator: std.mem.Allocator, mem: Memory, workspace_dir: []const u8) !usize

// ── Hydrate ───────────────────────────────────────────────────────

/// A parsed snapshot entry.
const SnapshotEntry = struct {

/// Restore memory entries from a JSON snapshot file.
/// Returns the number of entries hydrated.
pub fn hydrateFromSnapshot(allocator: std.mem.Allocator, mem: Memory, workspace_dir: []const u8) !usize

// ── Should hydrate ────────────────────────────────────────────────

/// Check if we should auto-hydrate on startup.
/// Returns true if memory is empty but snapshot file exists.
pub fn shouldHydrate(allocator: std.mem.Allocator, mem: ?Memory, workspace_dir: []const u8) bool

// ── Tests ─────────────────────────────────────────────────────────

test "shouldHydrate no memory no snapshot" {

test "shouldHydrate with non-empty memory" {

    // Create an in-memory SQLite for test
    var mem_impl = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");
    const mem = mem_impl.memory();

    // Store something

    // Should not hydrate because memory is not empty

test "exportSnapshot returns zero for empty memory" {

    var mem_impl = try sqlite_mod.SqliteMemory.init(std.testing.allocator, ":memory:");
    const mem = mem_impl.memory();

    const count = try exportSnapshot(std.testing.allocator, mem, "/tmp/yc_snapshot_test_nonexist");

test "SNAPSHOT_FILENAME is correct" {

// ── R3 Tests ──────────────────────────────────────────────────────

test "R3: snapshot export then import roundtrip preserves all entries" {

    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "R3: shouldHydrate returns true when memory is empty and snapshot exists" {

    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "R3: hydrateFromSnapshot with no file returns 0" {

    const allocator = std.testing.allocator;

    var mem_impl = try sqlite_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = mem_impl.memory();

    const hydrated = try hydrateFromSnapshot(allocator, mem, "/nonexistent_dir_xyz");
