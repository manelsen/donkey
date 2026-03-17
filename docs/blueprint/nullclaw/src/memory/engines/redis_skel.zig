//! Redis-backed persistent memory via RESP (REdis Serialization Protocol) over TCP.
//!
//! No C dependency — implements a minimal RESP v2 client directly.
//! Designed for distributed memory sharing across multiple nullclaw instances.

const std = @import("std");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;
const log = std.log.scoped(.redis_memory);

// ── RESP types ──────────────────────────────────────────────────────


    pub fn deinit(self: *RespValue, allocator: std.mem.Allocator) void

    /// Return the value as a string slice (simple_string or bulk_string).
    pub fn asString(self: RespValue) ?[]const u8

// ── RESP protocol helpers ───────────────────────────────────────────

/// Format a Redis command as a RESP array of bulk strings.
pub fn formatCommand(allocator: std.mem.Allocator, args: []const []const u8) ![]u8

/// Parse a single RESP value from the given data buffer.
/// Returns the parsed value and the number of bytes consumed.
pub fn parseResp(allocator: std.mem.Allocator, data: []const u8) !struct

// ── Redis config ────────────────────────────────────────────────────

pub const RedisConfig = struct {

// ── RedisMemory ─────────────────────────────────────────────────────

pub const RedisMemory = struct {

// ── Hash field parser ──────────────────────────────────────────────

fn parseHashFields(allocator: std.mem.Allocator, key: []const u8, fields: []RespValue) !MemoryEntry

// ── Tests ──────────────────────────────────────────────────────────

// RESP protocol tests (no Redis server needed)

test "formatCommand SET key value" {
    const cmd = try formatCommand(std.testing.allocator, &.{

test "formatCommand PING (no args)" {
    const cmd = try formatCommand(std.testing.allocator, &.{

test "formatCommand HSET multiple fields" {
    const cmd = try formatCommand(std.testing.allocator, &.{

test "formatCommand empty string arg" {
    const cmd = try formatCommand(std.testing.allocator, &.{

test "parseResp simple string" {
    const result = try parseResp(std.testing.allocator, "+OK\r\n");
    var val = result.value;

test "parseResp error" {
    const result = try parseResp(std.testing.allocator, "-ERR unknown\r\n");
    var val = result.value;

test "parseResp integer" {
    const result = try parseResp(std.testing.allocator, ":42\r\n");
    var val = result.value;

test "parseResp negative integer" {
    const result = try parseResp(std.testing.allocator, ":-1\r\n");
    var val = result.value;

test "parseResp bulk string" {
    const result = try parseResp(std.testing.allocator, "$5\r\nhello\r\n");
    var val = result.value;

test "parseResp null bulk string" {
    const result = try parseResp(std.testing.allocator, "$-1\r\n");
    var val = result.value;

test "parseResp empty bulk string" {
    const result = try parseResp(std.testing.allocator, "$0\r\n\r\n");
    var val = result.value;

test "parseResp array" {
    const data = "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n";
    const result = try parseResp(std.testing.allocator, data);
    var val = result.value;
    const arr = val.array.?;

test "parseResp null array" {
    const result = try parseResp(std.testing.allocator, "*-1\r\n");
    var val = result.value;

test "parseResp empty array" {
    const result = try parseResp(std.testing.allocator, "*0\r\n");
    var val = result.value;

test "parseResp nested array" {
    const data = "*2\r\n*2\r\n:1\r\n:2\r\n*1\r\n+OK\r\n";
    const result = try parseResp(std.testing.allocator, data);
    var val = result.value;
    const arr = val.array.?;
    const inner1 = arr[0].array.?;
    const inner2 = arr[1].array.?;

test "parseResp incomplete data returns error" {

test "parseResp unknown type returns error" {

test "parseResp mixed array" {
    const data = "*3\r\n:1\r\n$5\r\nhello\r\n+OK\r\n";
    const result = try parseResp(std.testing.allocator, data);
    var val = result.value;
    const arr = val.array.?;

test "parseHashFields basic" {
    // Simulate HGETALL response fields: [field, value, field, value, ...]

    var entry = try parseHashFields(std.testing.allocator, "test-key", &fields);


test "parseHashFields with session_id" {

    var entry = try parseHashFields(std.testing.allocator, "k", &fields);


test "parseHashFields custom category" {

    var entry = try parseHashFields(std.testing.allocator, "k", &fields);


test "RespValue deinit frees all memory" {
    // This test verifies no leaks via the testing allocator
    var val = RespValue{

test "formatCommand roundtrip with parseResp" {
    // Format a command and verify it starts with the right array header
    const cmd = try formatCommand(std.testing.allocator, &.{

// Integration tests — guarded by Redis availability
fn canConnectToRedis() bool

test "integration: redis store and get" {


    const m = mem.memory();

    // Clean up first




    // Cleanup

test "integration: redis count" {


    const m = mem.memory();

    // Store two entries

    const n = try m.count();

    // Cleanup

test "integration: redis recall substring" {


    const m = mem.memory();


    const results = try m.recall(std.testing.allocator, "brown fox", 10, null);


    // Cleanup

test "integration: redis forget" {


    const m = mem.memory();

    const ok = try m.forget("forget-me");

    const entry = try m.get(std.testing.allocator, "forget-me");

test "integration: redis health check" {



test "integration: redis name" {

    var mem = try RedisMemory.init(std.testing.allocator, .{
