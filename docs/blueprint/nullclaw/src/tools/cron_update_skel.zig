const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const cron = @import("../cron.zig");
const CronScheduler = cron.CronScheduler;
const loadScheduler = @import("cron_add.zig").loadScheduler;

/// CronUpdate tool — update a cron job's expression, command, or enabled state.
pub const CronUpdateTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "cron_update tool name" {
    var ct = CronUpdateTool{

test "cron_update schema has job_id" {
    var ct = CronUpdateTool{

test "cron_update_requires_job_id" {
    var ct = CronUpdateTool{

test "cron_update_requires_something" {
    var ct = CronUpdateTool{

test "cron_update_expression" {
    var ct = CronUpdateTool{

test "cron_update_disable" {
    var ct = CronUpdateTool{

test "cron_update_not_found" {
    var ct = CronUpdateTool{

test "cron_update_invalid_expression" {
    var ct = CronUpdateTool{
