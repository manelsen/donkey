//! SubagentManager — background task execution via isolated agent instances.
//!
//! Spawns subagents in separate OS threads with restricted tool sets
//! (no message, spawn, delegate — to prevent infinite loops).
//! Task results are routed via the event bus as system InboundMessages.

const std = @import("std");
const Allocator = std.mem.Allocator;
const bus_mod = @import("bus.zig");
const config_mod = @import("config.zig");
const config_types = @import("config_types.zig");
const providers = @import("providers/root.zig");
const thread_stacks = @import("thread_stacks.zig");

const log = std.log.scoped(.subagent);

// ── Task types ──────────────────────────────────────────────────

pub const TaskStatus = enum {

pub const TaskState = struct {

pub const SubagentConfig = struct {

pub const TaskRunRequest = struct {

pub const TaskRunnerFn = *const fn (allocator: Allocator, request: TaskRunRequest) anyerror![]const u8;

// ── ThreadContext — passed to each spawned thread ────────────────

const ThreadContext = struct {

// ── SubagentManager ─────────────────────────────────────────────

pub const SubagentManager = struct {
    // Context needed for creating providers in subagent threads

// ── Thread function ─────────────────────────────────────────────

fn subagentThreadFn(ctx: *ThreadContext) void

// ── Tests ───────────────────────────────────────────────────────

fn waitTaskTerminalStatus(manager: *SubagentManager, task_id: u64) !TaskStatus

fn testTaskRunnerOk(allocator: Allocator, request: TaskRunRequest) ![]const u8

fn testTaskRunnerFail(_: Allocator, _: TaskRunRequest) ![]const u8

test "SubagentManager init and deinit" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentConfig defaults" {
    const sc = SubagentConfig{

test "TaskStatus enum values" {

test "TaskState initial defaults" {

test "SubagentManager getRunningCount empty" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager getTaskStatus unknown id" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager getTaskResult unknown id" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager completeTask updates state" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager completeTask with error" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager completeTask routes via bus" {
    var bus = bus_mod.Bus.init();

    var mgr = SubagentManager.init(std.testing.allocator, &cfg, &bus, .{

test "SubagentManager spawn stores session key" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager spawnWithAgent rejects unknown agent" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager spawnWithAgent accepts configured agent" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager uses task runner callback result" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager stores runner callback error" {
    var mgr = SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "SubagentManager spawn rollback removes task on out-of-memory" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
