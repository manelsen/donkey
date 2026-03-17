//! Migration — import memory from OpenClaw workspaces.
//!
//! Mirrors ZeroClaw's migration module:
//!   - Reads from OpenClaw SQLite (brain.db) and Markdown (MEMORY.md, daily logs)
//!   - De-duplicates entries
//!   - Renames conflicting keys
//!   - Supports dry-run mode
//!   - Creates backup before import

const std = @import("std");
const platform = @import("platform.zig");
const Config = @import("config.zig").Config;
const fs_compat = @import("fs_compat.zig");
const memory_root = @import("memory/root.zig");
const migrate_mod = @import("memory/lifecycle/migrate.zig");

const log = std.log.scoped(.migration);

/// Policy for handling key conflicts during migration.
pub const MergePolicy = enum {
    /// Skip entries whose key already exists in the target (default safe mode).
    /// Overwrite target entry if the source content is different.
    /// Rename conflicting keys with a `_migrated_<hash>` suffix.

/// Statistics collected during migration.
pub const MigrationStats = struct {

/// A single entry from the source workspace.
pub const SourceEntry = struct {

/// Run the OpenClaw migration command.

/// Run the OpenClaw migration command with an explicit merge policy.
    const source = try resolveOpenclawWorkspace(allocator, source_path);

    // Verify source exists

    // Refuse self-migration

    var stats = MigrationStats{

// ── Config migration ─────────────────────────────────────────────

/// Copy OpenClaw config to nullclaw config with camelCase -> snake_case key
/// normalization.
    const source_config_path = try resolveOpenclawConfigPath(allocator, source_workspace);
    const source_config = source_config_path orelse return false;

    const src_file = try std.fs.openFileAbsolute(source_config, .{

/// Resolve OpenClaw config.json location from a workspace path.
/// Preferred layout is `<workspace parent>/config.json` for `~/.openclaw/workspace`.
fn resolveOpenclawConfigPath(allocator: std.mem.Allocator, source_workspace: []const u8) !?[]u8

fn normalizeConfigJsonKeysSnakeCase(allocator: std.mem.Allocator, json_content: []const u8) ![]u8

fn normalizeJsonValueKeys(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value

fn camelToSnakeKey(allocator: std.mem.Allocator, key: []const u8) ![]const u8

// ── Content hashing ─────────────────────────────────────────────

/// Compare two content strings for equality.
/// Direct comparison is both faster and correct (no hash collision risk).
fn contentEqual(a: []const u8, b: []const u8) bool

/// Produce a short hex hash (first 8 hex chars of SHA-256) for deterministic
/// conflict key suffixes.
pub fn contentShortHash(content: []const u8) [8]u8

// ── Backup ──────────────────────────────────────────────────────

/// Create a backup of the target database before import.
/// For SQLite backends, copies the .db file. For markdown, copies MEMORY.md.
/// Returns the backup file path (caller owns the string).
    const timestamp = std.time.timestamp();
    const backend = config.memory_backend;

        // SQLite-based backends: backup the memory.db file
        const db_file = try std.fs.path.join(allocator, &.{


/// Restore from a backup file by copying it over the current target.
/// The `backup_path` should be a path returned from `createBackup` or
/// following the naming convention `<target>.backup-<timestamp>`.
pub fn restoreBackup(backup_path: []const u8, target_path: []const u8) !void

fn copyFileAbsolute(src: []const u8, dst: []const u8) !void

/// Read OpenClaw markdown entries from MEMORY.md and daily logs.
    // Core memory file
    const core_path = try std.fmt.allocPrint(allocator, "{

/// Parse a markdown file into SourceEntry items.
    var count: usize = 0;
    var line_idx: usize = 0;
    var iter = std.mem.splitScalar(u8, content, '\n');
        const trimmed = std.mem.trim(u8, line, " \t\r");

        const clean = if (std.mem.startsWith(u8, trimmed, "- ")) trimmed[2..] else trimmed;

        // Try to parse structured format: **key**: value
        const parsed = parseStructuredLine(clean);



        const cat = try allocator.dupe(u8, category);


/// Parse a structured memory line: **key**: value
fn parseStructuredLine(line: []const u8) struct

/// Resolve the OpenClaw workspace directory.
fn resolveOpenclawWorkspace(allocator: std.mem.Allocator, source: ?[]const u8) ![]u8

/// Check if two paths refer to the same location.
fn pathsEqual(a: []const u8, b: []const u8) bool

/// Read brain.db entries from known locations, deduplicating against seen keys.
    // Try memory/brain.db (common OpenClaw layout)
    const paths = [_][]const u8{

// ── Errors ───────────────────────────────────────────────────────


// ── Tests ────────────────────────────────────────────────────────

test "parseStructuredLine parses bold key" {
    const result = parseStructuredLine("**user_pref**: likes Zig");

test "parseStructuredLine returns null for plain text" {
    const result = parseStructuredLine("plain note");

test "parseStructuredLine returns null for empty key" {
    const result = parseStructuredLine("****: some value");

test "parseMarkdownFile extracts entries" {
    const content = "# Title\n\n- **pref**: likes Zig\n- plain note\n\n# Section 2\nmore text\n";
    var entries: std.ArrayList(SourceEntry) = .empty;

    const count = try parseMarkdownFile(std.testing.allocator, content, "core", "test", &entries);

test "parseMarkdownFile skips headings and blank lines" {
    const content = "# Heading\n\n## Sub\n\n";
    var entries: std.ArrayList(SourceEntry) = .empty;

    const count = try parseMarkdownFile(std.testing.allocator, content, "core", "test", &entries);

test "pathsEqual detects same paths" {

test "resolveOpenclawWorkspace uses provided path" {
    const path = try resolveOpenclawWorkspace(std.testing.allocator, "/custom/workspace");

test "MigrationStats defaults to zero" {
    const stats = MigrationStats{

test "camelToSnakeKey converts camelCase and acronym keys" {
    const simple = try camelToSnakeKey(std.testing.allocator, "gatewayPort");

    const acronym = try camelToSnakeKey(std.testing.allocator, "HTTPRequestURL");

    const unchanged = try camelToSnakeKey(std.testing.allocator, "already_snake_case");

test "normalizeConfigJsonKeysSnakeCase rewrites nested keys" {
    const output = try normalizeConfigJsonKeysSnakeCase(std.testing.allocator, input);


test "resolveOpenclawConfigPath finds parent config for workspace layout" {
    var tmp = std.testing.tmpDir(.{

test "migrateOpenclawConfig copies and normalizes config json" {
    var tmp = std.testing.tmpDir(.{

// ── P5.2: Content hashing tests ──────────────────────────────────

test "contentEqual: identical short strings" {

test "contentEqual: different short strings" {

test "contentEqual: different lengths" {

test "contentEqual: identical long strings use hash path" {
    const long = "x" ** 128;

test "contentEqual: different long strings" {
    const a = "a" ** 128;
    const b = "b" ** 128;

test "contentShortHash: deterministic output" {
    const h1 = contentShortHash("likes Zig");
    const h2 = contentShortHash("likes Zig");

test "contentShortHash: different content yields different hash" {
    const h1 = contentShortHash("likes Zig");
    const h2 = contentShortHash("likes Rust");

test "contentShortHash: returns 8 hex chars" {
    const hash = contentShortHash("test content");

// ── P5.2: MergePolicy tests ─────────────────────────────────────

test "MergePolicy enum values" {
    // Verify all policy variants exist and are distinct
    const skip = MergePolicy.skip_existing;
    const overwrite = MergePolicy.overwrite_newer;
    const rename = MergePolicy.rename_conflicts;

// ── P5.3: Backup tests ──────────────────────────────────────────

test "backup and restore roundtrip" {
    // Create a temp file to act as source
    var tmp_dir = std.testing.tmpDir(.{

test "copyFileAbsolute fails on non-existent source" {
    const result = copyFileAbsolute("/tmp/nonexistent_migration_test_file_xyz.db", "/tmp/out.db");

// ── P5.1: Empty source yields zero entries ───────────────────────

test "parseMarkdownFile with empty content returns zero" {
    var entries: std.ArrayList(SourceEntry) = .empty;
    const count = try parseMarkdownFile(std.testing.allocator, "", "core", "empty", &entries);

test "parseMarkdownFile with whitespace-only content returns zero" {
    var entries: std.ArrayList(SourceEntry) = .empty;
    const count = try parseMarkdownFile(std.testing.allocator, "   \n  \n\t\n", "core", "ws", &entries);
