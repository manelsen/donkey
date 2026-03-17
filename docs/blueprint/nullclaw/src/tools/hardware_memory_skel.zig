const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

/// RAM base for STM32F401 Nucleo boards.
const NUCLEO_RAM_BASE: u64 = 0x2000_0000;

/// Maximum output size from probe-rs commands (64 KB).
const MAX_PROBE_OUTPUT: usize = 65_536;

/// Hardware memory read/write tool — read/write memory at addresses via probe-rs or serial.
/// Supports Nucleo boards connected via USB.
pub const HardwareMemoryTool = struct {

const proc = @import("process_util.zig");

/// Check if probe-rs is available on the system.
fn probeRsAvailable(allocator: std.mem.Allocator) bool

/// Execute a probe-rs read command: `probe-rs read --chip CHIP ADDRESS LENGTH`
fn probeRead(allocator: std.mem.Allocator, chip: []const u8, address: u64, length: usize) !ToolResult

/// Execute a probe-rs write command: `probe-rs write --chip CHIP ADDRESS VALUE`
fn probeWrite(allocator: std.mem.Allocator, chip: []const u8, address: u64, value: []const u8) !ToolResult

fn chipForBoard(board: []const u8) ?[]const u8

fn parseHexAddress(s: []const u8) ?u64

// ── Tests ───────────────────────────────────────────────────────────

test "hardware_memory tool name" {
    var hm = HardwareMemoryTool{

test "hardware_memory schema has action" {
    var hm = HardwareMemoryTool{

test "hardware_memory no boards returns error" {
    var hm = HardwareMemoryTool{

test "hardware_memory missing action returns error" {
    const boards = [_][]const u8{

test "hardware_memory unsupported board" {
    const boards = [_][]const u8{

test "hardware_memory read without probe-rs" {
    const boards = [_][]const u8{

test "hardware_memory write without probe-rs" {
    const boards = [_][]const u8{

test "hardware_memory write missing value" {
    const boards = [_][]const u8{

test "hardware_memory unknown action" {
    const boards = [_][]const u8{

test "parseHexAddress valid" {

test "parseHexAddress invalid" {

test "chipForBoard known" {

test "chipForBoard unknown" {
