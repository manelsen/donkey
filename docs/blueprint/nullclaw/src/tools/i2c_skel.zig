const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

/// Linux I2C ioctl constants.
const I2C_SLAVE = 0x0703;
const I2C_FUNCS = 0x0705;

/// Valid I2C address range (7-bit addressing, excluding reserved).
const I2C_ADDR_MIN: u7 = 0x03;
const I2C_ADDR_MAX: u7 = 0x77;

/// I2C hardware tool — detect buses, scan devices, read/write registers.
/// On non-Linux platforms, all actions return a platform-not-supported error.
pub const I2cTool = struct {

/// Parse hex address string (e.g. "0x48") and validate range 0x03-0x77.
pub fn parseAddress(args: JsonObjectMap) ?u7

// ── Tests ───────────────────────────────────────────────────────────

test "i2c tool name" {
    var it: I2cTool = .{

test "i2c tool description not empty" {
    var it: I2cTool = .{

test "i2c tool schema has action" {
    var it: I2cTool = .{

test "i2c detect on non-linux returns platform error" {
    if (comptime builtin.os.tag == .linux) return error.SkipZigTest;
    var it: I2cTool = .{

test "i2c scan on non-linux returns platform error" {
    if (comptime builtin.os.tag == .linux) return error.SkipZigTest;
    var it: I2cTool = .{

test "i2c read on non-linux returns platform error" {
    if (comptime builtin.os.tag == .linux) return error.SkipZigTest;
    var it: I2cTool = .{

test "i2c write on non-linux returns platform error" {
    if (comptime builtin.os.tag == .linux) return error.SkipZigTest;
    var it: I2cTool = .{

test "i2c missing action parameter" {
    var it: I2cTool = .{

test "i2c unknown action" {
    var it: I2cTool = .{

test "parseAddress valid hex" {
    const p1 = try root.parseTestArgs("{

test "parseAddress rejects out of range" {
    const p1 = try root.parseTestArgs("{

test "parseAddress rejects invalid" {
    const p1 = try root.parseTestArgs("{

test "i2c scan missing bus parameter" {
    if (comptime builtin.os.tag == .linux) return error.SkipZigTest;
    var it: I2cTool = .{
