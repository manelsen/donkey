const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const mem_root = @import("../memory/root.zig");
const Memory = mem_root.Memory;
const MemoryCategory = mem_root.MemoryCategory;

/// Memory store tool — lets the agent persist facts to long-term memory.
/// When a MemoryRuntime is available, also triggers vector sync after store.
pub const MemoryStoreTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "memory_store tool name" {
    var mt = MemoryStoreTool{

test "memory_store schema has key and content" {
    var mt = MemoryStoreTool{

test "memory_store executes without backend" {
    var mt = MemoryStoreTool{

test "memory_store missing key" {
    var mt = MemoryStoreTool{

test "memory_store missing content" {
    var mt = MemoryStoreTool{

test "memory_store with real backend" {
    const NoneMemory = mem_root.NoneMemory;
    var backend = NoneMemory.init();

    var mt = MemoryStoreTool{

test "memory_store default category is core" {
    const NoneMemory = mem_root.NoneMemory;
    var backend = NoneMemory.init();

    var mt = MemoryStoreTool{

test "memory_store with daily category" {
    const NoneMemory = mem_root.NoneMemory;
    var backend = NoneMemory.init();

    var mt = MemoryStoreTool{
