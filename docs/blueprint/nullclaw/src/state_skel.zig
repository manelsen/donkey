//! State Manager — persistent runtime state across daemon restarts.
//!
//! Stores last active channel/chat so heartbeat, cron, and other
//! components know where to route messages.
//! Persisted to `~/.nullclaw/state.json` with atomic writes (temp + rename).

const std = @import("std");
const json_util = @import("json_util.zig");
const Allocator = std.mem.Allocator;
const thread_stacks = @import("thread_stacks.zig");

/// Runtime state persisted to disk.
pub const State = struct {

/// Thread-safe state manager with file persistence.
pub const StateManager = struct {

/// Derive the default state file path from workspace dir.
pub fn defaultStatePath(allocator: Allocator, workspace_dir: []const u8) ![]u8

// ══════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════

const testing = std.testing;

test "State init defaults to null" {
    var s = State{

test "StateManager init and deinit — no leaks" {
    var mgr = try StateManager.init(testing.allocator, "/tmp/test-state.json");

test "StateManager setLastChannel and getLastChannel" {
    var mgr = try StateManager.init(testing.allocator, "/tmp/test-state.json");

    const before = mgr.getLastChannel();

    const after = mgr.getLastChannel();

test "StateManager setLastChannel overwrites previous" {
    var mgr = try StateManager.init(testing.allocator, "/tmp/test-state.json");


    const last = mgr.getLastChannel();

test "StateManager updated_at is set" {
    var mgr = try StateManager.init(testing.allocator, "/tmp/test-state.json");


test "StateManager save and load roundtrip" {
    var tmp = std.testing.tmpDir(.{

test "StateManager load missing file is ok" {
    var tmp = std.testing.tmpDir(.{

test "StateManager save with null values" {
    var tmp = std.testing.tmpDir(.{

test "StateManager save overwrites previous file" {
    var tmp = std.testing.tmpDir(.{

test "StateManager handles special chars in values" {
    var tmp = std.testing.tmpDir(.{

test "StateManager concurrent setLastChannel" {
    var mgr = try StateManager.init(testing.allocator, "/tmp/test-state-concurrent.json");

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;
            fn run(m: *StateManager, tid: usize) void

    // No crash, last_channel is set to something

test "defaultStatePath" {
    const path = try defaultStatePath(testing.allocator, "/home/user/.nullclaw");
