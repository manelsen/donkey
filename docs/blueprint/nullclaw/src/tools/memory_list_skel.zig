const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const mem_root = @import("../memory/root.zig");
const Memory = mem_root.Memory;
const MemoryCategory = mem_root.MemoryCategory;
const MemoryEntry = mem_root.MemoryEntry;

pub const MemoryListTool = struct {

test "memory_list tool name" {
    var mt = MemoryListTool{

test "memory_list executes without backend" {
    var mt = MemoryListTool{

test "memory_list filters internal keys by default" {
    const allocator = std.testing.allocator;
    var sqlite_mem = try mem_root.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    var mt = MemoryListTool{

test "memory_list include_internal true includes autosave entries" {
    const allocator = std.testing.allocator;
    var sqlite_mem = try mem_root.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    var mt = MemoryListTool{

test "memory_list filters markdown-encoded internal keys in content" {
    const allocator = std.testing.allocator;
    var sqlite_mem = try mem_root.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    var mt = MemoryListTool{

test "memory_list filters bootstrap internal keys by default" {
    const allocator = std.testing.allocator;
    var sqlite_mem = try mem_root.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();


    var mt = MemoryListTool{
