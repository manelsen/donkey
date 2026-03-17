const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const mem_root = @import("../memory/root.zig");
const Memory = mem_root.Memory;

/// Memory forget tool — lets the agent delete a memory entry.
/// When a MemoryRuntime is available, also cleans up the vector store.
pub const MemoryForgetTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "memory_forget tool name" {
    var mt = MemoryForgetTool{

test "memory_forget schema has key" {
    var mt = MemoryForgetTool{

test "memory_forget executes without backend" {
    var mt = MemoryForgetTool{

test "memory_forget missing key" {
    var mt = MemoryForgetTool{

test "memory_forget with real backend key not found" {
    const NoneMemory = mem_root.NoneMemory;
    var backend = NoneMemory.init();

    var mt = MemoryForgetTool{

test "memory_forget with real backend returns appropriate message" {
    const NoneMemory = mem_root.NoneMemory;
    var backend = NoneMemory.init();

    var mt = MemoryForgetTool{
