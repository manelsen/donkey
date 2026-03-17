const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const cron = @import("../cron.zig");
const CronScheduler = cron.CronScheduler;
const loadScheduler = @import("cron_add.zig").loadScheduler;

threadlocal var tls_schedule_channel: ?[]const u8 = null;
threadlocal var tls_schedule_account_id: ?[]const u8 = null;
threadlocal var tls_schedule_chat_id: ?[]const u8 = null;

/// Schedule tool — lets the agent manage recurring and one-shot scheduled tasks.
/// Delegates to the CronScheduler from the cron module for persistent job management.
pub const ScheduleTool = struct {
    /// Set the context for the current turn (called before agent.turn).

// ── Tests ───────────────────────────────────────────────────────────

test "schedule tool name" {
    var st = ScheduleTool{

test "schedule schema has action" {
    var st = ScheduleTool{

test "schedule list returns success" {
    var st = ScheduleTool{

test "schedule unknown action" {
    var st = ScheduleTool{

test "schedule create with expression" {
    var st = ScheduleTool{

test "schedule create rejects cross-channel override without explicit chat_id" {
    var st = ScheduleTool{

// ── Additional schedule tests ───────────────────────────────────

test "schedule missing action" {
    var st = ScheduleTool{

test "schedule get missing id" {
    var st = ScheduleTool{

test "schedule get nonexistent job" {
    var st = ScheduleTool{

test "schedule cancel requires id" {
    var st = ScheduleTool{

test "schedule cancel nonexistent job returns not found" {
    var st = ScheduleTool{

test "schedule remove nonexistent job returns not found" {
    var st = ScheduleTool{

test "schedule pause nonexistent job returns not found" {
    var st = ScheduleTool{

test "schedule resume nonexistent job returns not found" {
    var st = ScheduleTool{

test "schedule once creates one-shot task" {
    var st = ScheduleTool{

test "schedule add creates recurring job" {
    var st = ScheduleTool{

test "schedule create missing command" {
    var st = ScheduleTool{

test "schedule create missing expression" {
    var st = ScheduleTool{

test "schedule once missing delay" {
    var st = ScheduleTool{

test "schedule pause requires id" {
    var st = ScheduleTool{

test "schedule resume requires id" {
    var st = ScheduleTool{
