//! Explicit no-op memory backend.
//!
//! Used when `memory.backend = "none"` to disable persistence
//! while keeping the runtime wiring stable.

const std = @import("std");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;

pub const NoneMemory = struct {

// ── Tests ──────────────────────────────────────────────────────────

test "none memory is noop" {
    var mem = NoneMemory.init();
    const m = mem.memory();



    const got = try m.get(std.testing.allocator, "k");

    const recalled = try m.recall(std.testing.allocator, "k", 10, null);

    const listed = try m.list(std.testing.allocator, null, null);

    const forgotten = try m.forget("k");



test "none memory accepts session_id param" {
    var mem = NoneMemory.init();
    const m = mem.memory();

    // Store with session_id

    // Recall with session_id
    const recalled = try m.recall(std.testing.allocator, "k", 10, "session-123");

    // List with session_id
    const listed = try m.list(std.testing.allocator, null, "session-123");
