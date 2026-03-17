//! Doctor -- system diagnostics for nullclaw.
//!
//! Mirrors ZeroClaw's doctor module with severity-based diagnostics:
//!   - DiagItem system with ok/warn/err severity levels
//!   - Config semantic validation (provider, temperature, routes, channels)
//!   - Workspace integrity (writable probe, disk space, key files)
//!   - Daemon state with proper JSON parsing
//!   - Environment checks (git, curl, shell, home)
//!   - Sandbox, cron status, channel connectivity (nullclaw-specific)

const std = @import("std");
const platform = @import("platform.zig");
const Config = @import("config.zig").Config;
const channel_catalog = @import("channel_catalog.zig");
const daemon = @import("daemon.zig");
const cron = @import("cron.zig");
const fs_compat = @import("fs_compat.zig");
const builtin = @import("builtin");
const bootstrap_mod = @import("bootstrap/root.zig");
const BootstrapProvider = bootstrap_mod.BootstrapProvider;
const memory_root = @import("memory/root.zig");

/// Staleness thresholds (seconds).
const DAEMON_STALE_SECONDS: i64 = 30;
const SCHEDULER_STALE_SECONDS: i64 = 120;
const CHANNEL_STALE_SECONDS: i64 = 300;
const COMMAND_VERSION_PREVIEW_CHARS: usize = 60;
// ── ANSI color support ──────────────────────────────────────────

const Color = struct {

pub fn shouldColorize(file: std.fs.File) bool

/// Windows-specific: enable ENABLE_VIRTUAL_TERMINAL_PROCESSING on stdout.
fn enableWindowsVT100() !bool

// ── Diagnostic types ────────────────────────────────────────────

pub const Severity = enum {

pub const DiagItem = struct {

/// Legacy diagnostic result (kept for programmatic access).
pub const DiagResult = struct {

// ── Public entry point ──────────────────────────────────────────

/// Run the full doctor diagnostics suite.
    var items: std.ArrayList(DiagItem) = .empty;

    // Core checks (matching ZeroClaw)

    // nullclaw-specific extras

    // Print grouped report

    var current_cat: []const u8 = "";
    var ok_count: u32 = 0;
    var warn_count: u32 = 0;
    var err_count: u32 = 0;

        const ic = if (color) item.iconColored() else item.icon();


/// Legacy entry point — uses stdout directly.
pub fn run(allocator: std.mem.Allocator) !void

// ── Config semantic validation ──────────────────────────────────

    const cat = "config";

    // Default provider

    // API key

    // Default model

    // Temperature range

    // Gateway port

    // Fallback providers

    // Model routes

    // Channels: at least one non-CLI channel configured.
    // Use channel_catalog to avoid hardcoding channel lists in doctor checks.
    const has_channel = channel_catalog.hasAnyConfigured(config, false);


// ── Workspace integrity ─────────────────────────────────────────

    const cat = "workspace";
    const ws = config.workspace_dir;

    // Check directory exists
        var d = dir;

    // Writable probe
    const probe_name = ".nullclaw_doctor_probe";
    const probe_path = try std.fs.path.join(allocator, &.{

    // Use bootstrap provider when available.

    // Fallback: direct filesystem check.
    const dir = std.fs.openDirAbsolute(base_dir, .{

fn getDiskAvailableMb(allocator: std.mem.Allocator, path: []const u8) !?u64

pub fn parseDfAvailableMb(df_output: []const u8) ?u64

// ── Daemon state (proper JSON parsing) ──────────────────────────

    const cat = "daemon";

    const state_path = try daemon.stateFilePath(allocator, config);



    // Parse JSON

    const root = parsed.value;

    // Check status

    // Check updated_at timestamp for staleness
            const updated_at: i64 = ts_val.integer;
            const now: i64 = @intCast(std.time.timestamp());
            const age = now - updated_at;

    // Check components
            const components = &comps_val.object;

            // Scheduler

            // Count channel components
            var channel_count: u32 = 0;
            var stale_count: u32 = 0;
            var comp_it = components.iterator();


// ── Environment checks ──────────────────────────────────────────

    const cat = "env";

    // git

    // curl

    // $SHELL

    // $HOME

fn checkCommandAvailable(allocator: std.mem.Allocator, cmd: []const u8) !?[]const u8

pub fn truncateForDisplay(allocator: std.mem.Allocator, s: []const u8, max_len: usize) ![]const u8

// ── Nullclaw-specific checks ────────────────────────────────────

/// Check sandbox availability.
fn checkSandbox(allocator: std.mem.Allocator, cfg: *const Config, items: *std.ArrayList(DiagItem)) void

/// Check cron scheduler status.
fn checkCronStatus(allocator: std.mem.Allocator, items: *std.ArrayList(DiagItem)) !void

/// Check channel connectivity.
fn checkChannels(allocator: std.mem.Allocator, cfg: *const Config, items: *std.ArrayList(DiagItem)) void

/// Check a specific diagnostic (utility for programmatic access).
pub fn checkConfig(allocator: std.mem.Allocator) DiagResult

// ── Tests ────────────────────────────────────────────────────────

test "DiagItem.ok creates ok item" {
    const item = DiagItem.ok("test", "all good");

test "DiagItem.warn creates warn item" {
    const item = DiagItem.warn("test", "watch out");

test "DiagItem.err creates err item" {
    const item = DiagItem.err("test", "broken");

test "DiagItem.icon returns correct string" {

test "DiagItem.iconColored returns ANSI-colored strings" {
    const ok_icon = DiagItem.ok("t", "m").iconColored();

    const warn_icon = DiagItem.warn("t", "m").iconColored();

    const err_icon = DiagItem.err("t", "m").iconColored();

test "shouldColorize returns false for non-TTY file" {
    // Open /dev/null — it's not a TTY, so shouldColorize should return false
    const devnull = std.fs.openFileAbsolute("/dev/null", .{

test "checkConfigSemantics catches temperature out of range" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    var items: std.ArrayList(DiagItem) = .empty;

    var cfg = testConfig();

    var found_temp_err = false;

test "checkConfigSemantics accepts valid temperature" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    var items: std.ArrayList(DiagItem) = .empty;

    var cfg = testConfig();

    var found_temp_ok = false;

test "checkConfigSemantics warns empty default provider" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    var items: std.ArrayList(DiagItem) = .empty;

    var cfg = testConfig();

    var found_err = false;

test "checkConfigSemantics warns no channels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    var items: std.ArrayList(DiagItem) = .empty;

    const cfg = testConfig();

    var found_warn = false;

test "parseDfAvailableMb parses output" {
    const stdout = "Filesystem 1M-blocks Used Available Use% Mounted on\n/dev/sda1 1000 500 500 50% /\n";
    const result = parseDfAvailableMb(stdout);

test "parseDfAvailableMb returns null on empty" {

test "truncateForDisplay preserves UTF-8 boundaries" {
    const allocator = std.testing.allocator;
    const short = try truncateForDisplay(allocator, "hello world", 5);

test "truncateForDisplay no-op when short enough" {
    const allocator = std.testing.allocator;
    const same = try truncateForDisplay(allocator, "hi", 10);

test "checkEnvironment finds existing commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    var items: std.ArrayList(DiagItem) = .empty;


    // Should find at least $HOME on any dev machine
    var found_home = false;

test "checkDaemonState handles missing file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    var items: std.ArrayList(DiagItem) = .empty;

    var cfg = testConfig();


    var found_err = false;

test "checkDaemonState parses valid JSON state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();

    var tmp = std.testing.tmpDir(.{

test "staleness constants are reasonable" {

test "DiagResult defaults" {
    const result = DiagResult{

// ── Test helper ─────────────────────────────────────────────────

fn testConfig() Config
