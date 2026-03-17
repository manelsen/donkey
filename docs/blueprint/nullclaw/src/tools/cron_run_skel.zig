const std = @import("std");
const platform = @import("../platform.zig");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const cron = @import("../cron.zig");
const CronScheduler = cron.CronScheduler;
const loadScheduler = @import("cron_add.zig").loadScheduler;

/// CronRun tool — force-runs a cron job immediately by its ID, regardless of schedule.
pub const CronRunTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "cron_run tool name" {
    var crt = CronRunTool{

test "cron_run schema has job_id" {
    var crt = CronRunTool{

test "cron_run_requires_job_id" {
    var crt = CronRunTool{

test "cron_run_not_found" {
    var crt = CronRunTool{

test "cron_run_executes_command" {
    // Create a scheduler with a job, save it, then run via tool
    var scheduler = CronScheduler.init(std.testing.allocator, 10, true);

    const job = try scheduler.addJob("*/5 * * * *", "echo hello");
    const job_id = try std.testing.allocator.dupe(u8, job.id);


    // Now execute the cron_run tool
    var crt = CronRunTool{
