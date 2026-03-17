const std = @import("std");
const observability = @import("observability.zig");
const bootstrap_mod = @import("bootstrap/root.zig");
const BootstrapProvider = bootstrap_mod.BootstrapProvider;

const MAX_HEARTBEAT_FILE_BYTES: usize = 64 * 1024;

pub const TickOutcome = enum {

pub const TickResult = struct {

/// Heartbeat engine — reads HEARTBEAT.md and processes periodic tasks.
pub const HeartbeatEngine = struct {

fn isMarkdownBulletPrefix(ch: u8) bool

fn isMarkdownHeader(line: []const u8) bool

fn isEmptyMarkdownBullet(line: []const u8) bool

// ── Tests ────────────────────────────────────────────────────────────

test "parseTasks basic" {
    const allocator = std.testing.allocator;
    const content = "# Tasks\n\n- Check email\n- Review calendar\nNot a task\n- Third task";
    const tasks = try HeartbeatEngine.parseTasks(allocator, content);

test "parseTasks empty content" {
    const allocator = std.testing.allocator;
    const tasks = try HeartbeatEngine.parseTasks(allocator, "");

test "parseTasks only comments" {
    const allocator = std.testing.allocator;
    const tasks = try HeartbeatEngine.parseTasks(allocator, "# No tasks here\n\nJust comments\n# Another");

test "parseTasks with leading whitespace" {
    const allocator = std.testing.allocator;
    const content = "  - Indented task\n\t- Tab indented";
    const tasks = try HeartbeatEngine.parseTasks(allocator, content);

test "parseTasks dash without space ignored" {
    const allocator = std.testing.allocator;
    const content = "- Real task\n-\n- Another";
    const tasks = try HeartbeatEngine.parseTasks(allocator, content);

test "parseTasks trailing space bullet skipped" {
    const allocator = std.testing.allocator;
    const content = "- ";
    const tasks = try HeartbeatEngine.parseTasks(allocator, content);

test "parseTasks unicode" {
    const allocator = std.testing.allocator;
    const content = "- Check email \xf0\x9f\x93\xa7\n- Review calendar \xf0\x9f\x93\x85";
    const tasks = try HeartbeatEngine.parseTasks(allocator, content);

test "parseTasks single task" {
    const allocator = std.testing.allocator;
    const tasks = try HeartbeatEngine.parseTasks(allocator, "- Only one");

test "parseTasks mixed markdown" {
    const allocator = std.testing.allocator;
    const content = "# Periodic Tasks\n\n## Quick\n- Task A\n\n## Long\n- Task B\n\n* Not a dash bullet\n1. Not numbered";
    const tasks = try HeartbeatEngine.parseTasks(allocator, content);

test "HeartbeatEngine init clamps interval" {
    const engine = HeartbeatEngine.init(true, 2, "/tmp", null);

test "HeartbeatEngine init preserves valid interval" {
    const engine = HeartbeatEngine.init(true, 30, "/tmp", null);

test "isContentEffectivelyEmpty mirrors OpenClaw file gating semantics" {
