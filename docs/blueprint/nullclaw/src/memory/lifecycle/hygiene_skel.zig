//! Memory hygiene — periodic cleanup of old daily memories, archives, and conversation rows.
//!
//! Mirrors ZeroClaw's hygiene module:
//!   - run_if_due: checks last_hygiene_at in kv table, runs if older than interval
//!   - Archives old daily memory files
//!   - Purges expired archives
//!   - Prunes old conversation rows from SQLite

const std = @import("std");
const build_options = @import("build_options");
const fs_compat = @import("../../fs_compat.zig");
const root = @import("../root.zig");
const Memory = root.Memory;
const sqlite_mod = if (build_options.enable_sqlite) @import("../engines/sqlite.zig") else @import("../engines/sqlite_disabled.zig");
const chunker = @import("../vector/chunker.zig");
const log = std.log.scoped(.memory_hygiene);

/// Default hygiene interval in seconds (12 hours).
const HYGIENE_INTERVAL_SECS: i64 = 12 * 60 * 60;
const ARCHIVE_READ_MAX_BYTES: usize = 1024 * 1024;
const ARCHIVE_CHUNK_MAX_TOKENS: usize = 512;
const ARCHIVE_CATEGORY = root.MemoryCategory{