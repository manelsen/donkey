const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const mem_root = @import("../memory/root.zig");
const Memory = mem_root.Memory;
const MemoryEntry = mem_root.MemoryEntry;

/// Memory recall tool — lets the agent search its own memory.
/// When a MemoryRuntime is available, uses the full retrieval pipeline
/// (hybrid search, RRF merge, temporal decay, MMR, etc.) instead of
/// raw `mem.recall()`.
pub const MemoryRecallTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "memory_recall tool name" {
    var mt = MemoryRecallTool{

test "memory_recall schema has query" {
    var mt = MemoryRecallTool{

test "memory_recall executes without backend" {
    var mt = MemoryRecallTool{

test "memory_recall missing query" {
    var mt = MemoryRecallTool{

test "memory_recall with real backend empty result" {
    const NoneMemory = mem_root.NoneMemory;
    var backend = NoneMemory.init();

    var mt = MemoryRecallTool{

test "memory_recall with custom limit" {
    const NoneMemory = mem_root.NoneMemory;
    var backend = NoneMemory.init();

    var mt = MemoryRecallTool{

test "memory_recall filters internal bootstrap keys" {
    const allocator = std.testing.allocator;
    var sqlite_mem = try mem_root.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    var mt = MemoryRecallTool{
