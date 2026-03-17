const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const cron = @import("../cron.zig");
const CronScheduler = cron.CronScheduler;
const loadScheduler = @import("cron_add.zig").loadScheduler;

/// CronList tool — lists all scheduled cron jobs with their status and next run time.
pub const CronListTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "cron_list_empty" {
    // An empty scheduler should produce no formatted output
    var scheduler = CronScheduler.init(std.testing.allocator, 10, true);

    const jobs = scheduler.listJobs();

test "cron_list_with_jobs" {
    var scheduler = CronScheduler.init(std.testing.allocator, 10, true);

    const job = try scheduler.addJob("*/5 * * * *", "echo hello");

    // Format output the same way the tool does, to verify content
    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(std.testing.allocator);
    const status: []const u8 = if (job.paused) "paused" else "enabled";
    const output = buf.items;

test "cron_list_shows_paused" {
    var scheduler = CronScheduler.init(std.testing.allocator, 10, true);

    const job = try scheduler.addJob("0 * * * *", "echo paused_test");

    const jobs = scheduler.listJobs();

    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(std.testing.allocator);
    const status: []const u8 = if (jobs[0].paused) "paused" else "enabled";
    const output = buf.items;

test "cron_list tool name" {
    var cl = CronListTool{

test "cron_list tool parameters" {
    var cl = CronListTool{