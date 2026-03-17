const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const SubagentManager = @import("../subagent.zig").SubagentManager;

/// Spawn tool — launches a background subagent to work on a task asynchronously.
/// Returns a task ID immediately. Results are delivered as system messages.
pub const SpawnTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "spawn tool name" {
    var st = SpawnTool{

test "spawn tool description" {
    var st = SpawnTool{

test "spawn tool schema has task" {
    var st = SpawnTool{

test "spawn missing task parameter" {
    var st = SpawnTool{

test "spawn empty task rejected" {
    var st = SpawnTool{

test "spawn blank agent rejected" {
    var st = SpawnTool{

test "spawn without manager fails" {
    var st = SpawnTool{

test "spawn empty JSON rejected" {
    var st = SpawnTool{

test "spawn with unknown named agent fails" {
    const subagent = @import("../subagent.zig");
    const config = @import("../config.zig");

    var manager = subagent.SubagentManager.init(std.testing.allocator, &cfg, null, .{
