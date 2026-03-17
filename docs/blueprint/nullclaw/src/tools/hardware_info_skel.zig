const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

/// Static board info entries: (board_id, chip, description).
const BoardInfo = struct {


/// Hardware board info tool — returns chip name, architecture, and memory map.
pub const HardwareBoardInfoTool = struct {

fn memoryMapStatic(board: []const u8) ?[]const u8

// ── Tests ───────────────────────────────────────────────────────────

test "hardware_board_info tool name" {
    var hi = HardwareBoardInfoTool{

test "hardware_board_info schema has board" {
    var hi = HardwareBoardInfoTool{

test "hardware_board_info no boards returns error" {
    var hi = HardwareBoardInfoTool{

test "hardware_board_info known board returns info" {
    const boards = [_][]const u8{

test "hardware_board_info default board from config" {
    const boards = [_][]const u8{

test "hardware_board_info unknown board returns message" {
    const boards = [_][]const u8{

test "hardware_board_info esp32" {
    const boards = [_][]const u8{

test "memoryMapStatic returns for known boards" {
