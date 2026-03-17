const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const cron = @import("../cron.zig");
const CronScheduler = cron.CronScheduler;
const loadScheduler = @import("cron_add.zig").loadScheduler;

/// Cron runs tool — shows execution history for a cron job.
pub const CronRunsTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "cron_runs_requires_job_id" {
    var crt = CronRunsTool{

test "cron_runs_not_found" {
    var crt = CronRunsTool{

test "cron_runs_no_history" {
    const allocator = std.testing.allocator;
    // Create a scheduler with a job but no runs (no file I/O)
    var scheduler = CronScheduler.init(allocator, 10, true);
    const job = try scheduler.addJob("* * * * *", "echo test");
    const job_id = job.id;

    // Verify no runs exist
    const runs = try scheduler.listRuns(allocator, job_id, 10);

    // Also verify via tool with a nonexistent job (since tool loads from disk)
    var crt = CronRunsTool{

test "cron_runs_shows_history" {
    const allocator = std.testing.allocator;
    // Create a scheduler with a job and add runs directly (no file I/O)
    var scheduler = CronScheduler.init(allocator, 10, true);

    const job = try scheduler.addJob("*/5 * * * *", "echo hello");
    const job_id = job.id;


    // Verify runs are stored
    const runs = try scheduler.listRuns(allocator, job_id, 10);

test "cron_runs tool name" {
    var crt = CronRunsTool{

test "cron_runs schema has job_id" {
    var crt = CronRunsTool{
