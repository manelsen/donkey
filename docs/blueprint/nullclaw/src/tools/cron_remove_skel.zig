const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const cron = @import("../cron.zig");
const CronScheduler = cron.CronScheduler;
const loadScheduler = @import("cron_add.zig").loadScheduler;

/// CronRemove tool — removes a scheduled cron job by its ID.
pub const CronRemoveTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "cron_remove_requires_job_id" {
    var t = CronRemoveTool{

test "cron_remove_not_found" {
    var t = CronRemoveTool{

test "cron_remove_success" {
    // First, create a job via the scheduler directly
    var scheduler = CronScheduler.init(std.testing.allocator, 10, true);
    const job = try scheduler.addJob("*/5 * * * *", "echo test");
    const job_id = try std.testing.allocator.dupe(u8, job.id);

    // Now remove it via the tool
    var t = CronRemoveTool{

test "cron_remove tool name" {
    var t = CronRemoveTool{

test "cron_remove schema has job_id" {
    var t = CronRemoveTool{

test "cron_remove empty job_id" {
    var t = CronRemoveTool{
