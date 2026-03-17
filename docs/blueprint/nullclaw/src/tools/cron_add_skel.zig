const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const cron = @import("../cron.zig");
const CronScheduler = cron.CronScheduler;

/// CronAdd tool — creates a new cron job with either a cron expression or a delay.
pub const CronAddTool = struct {

/// Load the CronScheduler from persisted state (~/.nullclaw/cron.json).
/// Shared by cron_add, cron_list, cron_remove, and schedule tools.
pub fn loadScheduler(allocator: std.mem.Allocator) !CronScheduler

// ── Tests ───────────────────────────────────────────────────────────

test "cron_add_requires_command" {
    var cat = CronAddTool{

test "cron_add_requires_schedule" {
    var cat = CronAddTool{

test "cron_add_with_expression" {
    var cat = CronAddTool{

test "cron_add_with_delay" {
    var cat = CronAddTool{

test "cron_add_rejects_invalid_expression" {
    var cat = CronAddTool{

test "cron_add tool name" {
    var cat = CronAddTool{

test "cron_add schema has command" {
    var cat = CronAddTool{
