//! SQLite-backed persistent memory — the brain.
//!
//! Features:
//! - Core memories table with CRUD
//! - FTS5 full-text search with BM25 scoring
//! - FTS5 sync triggers (insert/update/delete)
//! - Upsert semantics (ON CONFLICT DO UPDATE)
//! - Session-scoped memory isolation via session_id
//! - Session message storage (legacy compat)
//! - KV store for settings

const std = @import("std");
const builtin = @import("builtin");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;
const log = std.log.scoped(.memory_sqlite);


pub const SQLITE_STATIC: c.sqlite3_destructor_type = null;
const BUSY_TIMEOUT_MS: c_int = 5000;

/// Detect whether the filesystem backing `path` supports WAL mode (which
/// requires mmap).  On Linux, 9p / NFS / CIFS do not support mmap, so we
/// fall back to DELETE journal mode for those.  On non-Linux or on statfs
/// failure we default to WAL (the common case).
///
/// Primary detection: parse `/proc/self/mountinfo` to find the fs_type for
/// the longest matching mount_point prefix.  This correctly identifies 9p
/// even when statfs reports the host's backing filesystem magic (e.g. ZFS).
///
/// Fallback: statfs syscall (catches cases where mountinfo is unavailable).
pub fn shouldUseWal(path: [*:0]const u8) bool

/// Parse /proc/self/mountinfo to find the filesystem type for `path`.
/// Returns `false` if the fs is 9p/nfs/cifs/smb3, `true` for others,
/// `null` if mountinfo is unavailable or unparseable.
fn checkMountinfo(path: []const u8) ?bool

/// Parse one mountinfo line and update best match if mount_point is a
/// longer prefix of `path`.
///
/// Format: mount_id parent_id major:minor root mount_point flags [opts]* - fs_type source super_opts
fn parseMountinfoLine(line: []const u8, path: []const u8, best_len: *usize, best_is_network: *bool) void

fn mountPointDecodedPrefixLen(path: []const u8, mount_point: []const u8) ?usize

fn octalDigit(ch: u8) ?u8

fn isNetworkFs(fs_type: []const u8) bool

/// Fallback: use statfs to check f_type. If the DB file does not exist yet,
/// retry on its parent directory.
fn checkStatfs(path: [*:0]const u8) bool

fn statfsSupportsWal(path: [*:0]const u8) ?bool

pub const SqliteMemory = struct {

// ── Tests ──────────────────────────────────────────────────────────

test "mountinfo parser decodes escaped mount point and picks network fs" {
    const path = "/mnt/My Drive/work/memory.db";
    const root_line = "24 1 0:21 / / rw,relatime - ext4 /dev/root rw";
    const share_line = "36 24 0:31 / /mnt/My\\040Drive rw,relatime - 9p drvfs rw";

    var best_len: usize = 0;
    var best_is_network = false;


test "mountinfo parser enforces directory boundary on prefix matches" {
    const line = "36 24 0:31 / /mnt/share rw,relatime - 9p drvfs rw";
    const path = "/mnt/share2/memory.db";

    var best_len: usize = 0;
    var best_is_network = false;


test "sqlite memory init with in-memory db" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

test "sqlite init configures busy timeout" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    var stmt: ?*c.sqlite3_stmt = null;
    const prep_rc = c.sqlite3_prepare_v2(mem.db, "PRAGMA busy_timeout;", -1, &stmt, null);

    const step_rc = c.sqlite3_step(stmt);
    const timeout_ms = c.sqlite3_column_int(stmt, 0);

test "sqlite name" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

test "sqlite health check" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

test "sqlite store and get" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = try m.get(std.testing.allocator, "user_lang");


test "sqlite store upsert" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = try m.get(std.testing.allocator, "pref");

    const cnt = try m.count();

test "sqlite recall keyword" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "Zig", 10, null);


test "sqlite recall no match" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "javascript", 10, null);


test "sqlite recall empty query" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "", 10, null);

test "sqlite recall whitespace query" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "   ", 10, null);

test "sqlite forget" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const removed = try m.forget("temp");

test "sqlite forget nonexistent" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    const removed = try m.forget("nope");

test "sqlite list all" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const all = try m.list(std.testing.allocator, null, null);

test "sqlite list by category" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const core_list = try m.list(std.testing.allocator, .core, null);

    const daily_list = try m.list(std.testing.allocator, .daily, null);

test "sqlite count empty" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

test "sqlite get nonexistent" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    const entry = try m.get(std.testing.allocator, "nope");

test "sqlite category roundtrip" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const e0 = (try m.get(std.testing.allocator, "k0")).?;

    const e1 = (try m.get(std.testing.allocator, "k1")).?;

    const e2 = (try m.get(std.testing.allocator, "k2")).?;

    const e3 = (try m.get(std.testing.allocator, "k3")).?;

test "sqlite forget then recall no ghost results" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "phantom memory", 10, null);

test "sqlite forget and re-store same key" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "cycle")).?;

test "sqlite store empty content" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    const entry = (try m.get(std.testing.allocator, "empty")).?;

test "sqlite store empty key" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    const entry = (try m.get(std.testing.allocator, "")).?;

test "sqlite recall results have scores" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "scored", 10, null);


test "sqlite reindex" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    try m.store("r1", "reindex test alpha", .core, null);
    try m.store("r2", "reindex test beta", .core, null);


    const results = try m.recall(std.testing.allocator, "reindex", 10, null);

test "sqlite recall with sql injection attempt" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "'; DROP TABLE memories; --", 10, null);


test "sqlite schema has fts5 table" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    const sql = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='memories_fts'";
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(mem.db, sql, -1, &stmt, null);

    const count = c.sqlite3_column_int64(stmt, 0);

test "sqlite fts5 syncs on insert" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const sql = "SELECT COUNT(*) FROM memories_fts WHERE memories_fts MATCH '\"unique_searchterm_xyz\"'";
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(mem.db, sql, -1, &stmt, null);


test "sqlite fts5 syncs on delete" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const sql = "SELECT COUNT(*) FROM memories_fts WHERE memories_fts MATCH '\"deletable_content_abc\"'";
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(mem.db, sql, -1, &stmt, null);


test "sqlite fts5 syncs on update" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


        const sql = "SELECT COUNT(*) FROM memories_fts WHERE memories_fts MATCH '\"original_content_111\"'";
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(mem.db, sql, -1, &stmt, null);

        const sql = "SELECT COUNT(*) FROM memories_fts WHERE memories_fts MATCH '\"updated_content_222\"'";
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(mem.db, sql, -1, &stmt, null);

test "sqlite list custom category" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const project = try m.list(std.testing.allocator, .{

test "sqlite list empty db" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    const all = try m.list(std.testing.allocator, null, null);

test "sqlite recall matches by key not just content" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "zig", 10, null);


test "sqlite recall respects limit" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "key_{

    const results = try m.recall(std.testing.allocator, "searchable", 3, null);


test "sqlite store unicode content" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "unicode_key")).?;

test "sqlite recall unicode query" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e", 10, null);


test "sqlite store long content" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    // Build a long string
    var buf: std.ArrayList(u8) = .empty;

    const entry = (try m.get(std.testing.allocator, "long")).?;

test "sqlite multiple categories count" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();



test "sqlite saveMessage stores messages" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");


    // Verify messages table has data
    const sql = "SELECT COUNT(*) FROM messages";
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(mem.db, sql, -1, &stmt, null);


test "sqlite store and forget multiple keys" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();





test "sqlite upsert changes category" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "key")).?;

test "sqlite recall multi-word query" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "systems programming", 10, null);


test "sqlite list returns all entries" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const all = try m.list(std.testing.allocator, null, null);


    // All keys should be present
    var found_first = false;
    var found_second = false;
    var found_third = false;

test "sqlite get returns entry with all fields" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "test_key")).?;


test "sqlite recall with quotes in query" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "hello", 10, null);


test "sqlite health check after operations" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();



test "sqlite kv table exists" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    const sql = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='kv'";
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(mem.db, sql, -1, &stmt, null);


// ── Session ID tests ──────────────────────────────────────────────

test "sqlite store with session_id persists" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "k1")).?;


test "sqlite store without session_id gives null" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "k1")).?;


test "sqlite recall with session_id filters correctly" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    // Recall with session-a filter returns only session-a entry
    const results = try m.recall(std.testing.allocator, "fact", 10, "sess-a");


test "sqlite recall with null session_id returns all" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "fact", 10, null);


test "sqlite list with session_id filter" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    // List with session-a filter
    const results = try m.list(std.testing.allocator, null, "sess-a");


test "sqlite list with session_id and category filter" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const results = try m.list(std.testing.allocator, .core, "sess-a");


test "sqlite cross-session recall isolation" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    // Session B cannot see session A data
    const results_b = try m.recall(std.testing.allocator, "secret", 10, "sess-b");

    // Session A can see its own data
    const results_a = try m.recall(std.testing.allocator, "secret", 10, "sess-a");

test "sqlite schema has session_id column" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    // Verify session_id column exists by querying it
    const sql = "SELECT session_id FROM memories LIMIT 0";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(mem.db, sql, -1, &stmt, null);

test "sqlite schema migration is idempotent" {
    // Calling migrateSessionId twice should not fail
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    // migrateSessionId already ran during init; call it again

    // Store with session_id should still work
    const m = mem.memory();
    const entry = (try m.get(std.testing.allocator, "k1")).?;

// ── clearAutoSaved tests ──────────────────────────────────────────

test "sqlite clearAutoSaved removes autosave entries" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();




    const entry = (try m.get(std.testing.allocator, "normal_key")).?;

test "sqlite clearAutoSaved scoped by session_id" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();



    const a_entry = try m.get(std.testing.allocator, "autosave_user_a");

    const b_entry = try m.get(std.testing.allocator, "autosave_user_b");

    const normal = try m.get(std.testing.allocator, "normal_key");

test "sqlite clearAutoSaved preserves non-autosave entries" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();



    // "autosave_like_prefix" starts with "autosave_" so it IS removed

test "sqlite clearAutoSaved no-op on empty" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    const m = mem.memory();

// ── SessionStore vtable tests ─────────────────────────────────────

test "sqlite sessionStore returns valid vtable" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    const store = mem.sessionStore();

test "sqlite sessionStore saveMessage + loadMessages roundtrip" {
    const allocator = std.testing.allocator;
    var mem = try SqliteMemory.init(allocator, ":memory:");

    const store = mem.sessionStore();

    const msgs = try store.loadMessages(allocator, "s1");


test "sqlite sessionStore history views hide runtime command rows" {
    const allocator = std.testing.allocator;
    var mem = try SqliteMemory.init(allocator, ":memory:");

    const store = mem.sessionStore();

    const raw = try store.loadMessages(allocator, "s1");


    const sessions = try store.listSessions(allocator, 10, 0);


    const detailed = try store.loadMessagesDetailed(allocator, "s1", 10, 0);

test "sqlite sessionStore clearMessages" {
    const allocator = std.testing.allocator;
    var mem = try SqliteMemory.init(allocator, ":memory:");

    const store = mem.sessionStore();

    const msgs = try store.loadMessages(allocator, "s1");

test "sqlite sessionStore saveUsage + loadUsage roundtrip" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    const store = mem.sessionStore();

test "sqlite sessionStore clearAutoSaved" {
    const allocator = std.testing.allocator;
    var mem = try SqliteMemory.init(allocator, ":memory:");

    const m = mem.memory();

    const store = mem.sessionStore();

    // autosave entry should be gone
    const entry = try m.get(allocator, "autosave_user_1");

    // normal entry should remain
    const normal = try m.get(allocator, "normal_key");
    var e = normal.?;

// ── R3 additional tests ───────────────────────────────────────────

test "sqlite recall with SQL LIKE wildcard percent in content" {
    // Verify that % in search query does not match everything
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    // Searching for "%" should NOT match "completely unrelated"
    // because % is escaped in LIKE patterns
    const results = try m.recall(std.testing.allocator, "%", 10, null);

    // FTS5 may or may not match "%" — but LIKE fallback must not wildcard-match everything.
    // If FTS5 returns 0 results (likely for single %), the LIKE search must be precise.
        // Every returned result must actually contain "%" in key or content

test "sqlite recall with SQL LIKE wildcard underscore in content" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    // Searching for "_" should not match "testXvalue" via LIKE _
    // (underscore matches single char in unescaped LIKE)
    const results = try m.recall(std.testing.allocator, "_", 10, null);


test "sqlite escapeLikePattern escapes wildcards" {
    const alloc = std.testing.allocator;

    // Normal word — just wrapped with %
        const result = try SqliteMemory.escapeLikePattern(alloc, "hello");

    // Percent sign — escaped
        const result = try SqliteMemory.escapeLikePattern(alloc, "100%");

    // Underscore — escaped
        const result = try SqliteMemory.escapeLikePattern(alloc, "test_value");

    // Backslash — escaped
        const result = try SqliteMemory.escapeLikePattern(alloc, "path\\to");

    // Empty string
        const result = try SqliteMemory.escapeLikePattern(alloc, "");

test "sqlite store and get with special chars in key" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    const key = "key with \"quotes\" and 'apostrophes' and %wildcards%";

    const entry = (try m.get(std.testing.allocator, key)).?;

test "sqlite store newlines in content roundtrip" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

    const content = "line1\nline2\ttab\r\nwindows\n\ndouble newline";

    const entry = (try m.get(std.testing.allocator, "nl")).?;

test "sqlite upsert updates session_id from null to value" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();

        const entry = (try m.get(std.testing.allocator, "k")).?;

        const entry = (try m.get(std.testing.allocator, "k")).?;

test "sqlite upsert updates session_id from value to null" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");
    const m = mem.memory();


    const entry = (try m.get(std.testing.allocator, "k")).?;

test "sqlite loadMessages empty session" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");

    const msgs = try mem.loadMessages(std.testing.allocator, "nonexistent");

test "sqlite loadMessages preserves order" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");


    const msgs = try mem.loadMessages(std.testing.allocator, "s1");


test "sqlite clearMessages does not affect other sessions" {
    var mem = try SqliteMemory.init(std.testing.allocator, ":memory:");



    const s1_msgs = try mem.loadMessages(std.testing.allocator, "s1");

    const s2_msgs = try mem.loadMessages(std.testing.allocator, "s2");
