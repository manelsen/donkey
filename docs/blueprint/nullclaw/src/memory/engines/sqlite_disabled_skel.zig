//! SQLite disabled shim.
//!
//! Provides minimal sqlite3 symbols/types so modules can compile when
//! SQLite runtime support is excluded from the build (for example, when
//! `-Dengines` does not include sqlite/lucid/lancedb).

const std = @import("std");
const builtin = @import("builtin");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;

pub const c = struct {

pub const SQLITE_STATIC: c.sqlite3_destructor_type = null;

pub const SqliteMemory = struct {
