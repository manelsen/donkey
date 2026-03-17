//! MCP (Model Context Protocol) client.
//!
//! Supports stdio and HTTP JSON-RPC transports. Wraps discovered tools into
//! the standard Tool vtable so the agent can call them like any built-in tool.

const std = @import("std");
const tools_mod = @import("tools/root.zig");
const config_mod = @import("config.zig");
const json_util = @import("json_util.zig");
const version = @import("version.zig");
const platform = @import("platform.zig");
const http_util = @import("http_util.zig");
const verbose = @import("verbose.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.mcp);

pub const McpServerConfig = config_mod.McpServerConfig;

// ── Tool definition from server ─────────────────────────────────

pub const McpToolDef = struct {

// ── McpServer — child process lifecycle ─────────────────────────

pub const McpServer = struct {

// ── Response parsers ────────────────────────────────────────────

pub fn parseToolsListResponse(allocator: Allocator, resp: []const u8) ![]McpToolDef

pub fn parseCallToolResponse(allocator: Allocator, resp: []const u8) ![]const u8

// ── McpToolWrapper — adapts MCP tool to Tool vtable ─────────────

pub const McpToolWrapper = struct {

// ── Top-level init ──────────────────────────────────────────────

/// Initialize MCP tools from config. Connects to each server, discovers
/// tools, and returns them wrapped in the standard Tool vtable.
/// Errors from individual servers are logged and skipped.
pub fn initMcpTools(allocator: Allocator, configs: []const McpServerConfig) ![]tools_mod.Tool

// ── Tests ───────────────────────────────────────────────────────

test "McpServer init fields" {
    const server = McpServer.init(std.testing.allocator, cfg);

test "McpServer sendRequest requires http client for http transport" {

test "McpServer sendNotification propagates http transport setup errors" {

test "McpServer init http fields" {
    const server = McpServer.init(std.testing.allocator, cfg);

test "parseToolsListResponse valid" {
    const defs = try parseToolsListResponse(std.testing.allocator, resp);

test "parseToolsListResponse empty tools" {
    const defs = try parseToolsListResponse(std.testing.allocator, resp);

test "parseToolsListResponse error" {

test "parseCallToolResponse valid" {
    const output = try parseCallToolResponse(std.testing.allocator, resp);

test "parseCallToolResponse multiple content" {
    const output = try parseCallToolResponse(std.testing.allocator, resp);

test "parseCallToolResponse error" {

test "parseCallToolResponse invalid json" {

test "McpToolWrapper vtable name" {
    const t = wrapper.tool();

test "McpToolWrapper vtable description" {
    const t = wrapper.tool();

test "McpToolWrapper vtable parameters_json" {
    const t = wrapper.tool();

test "initMcpTools empty configs" {
    const tools = try initMcpTools(std.testing.allocator, &.{

test "buildJsonRpcRequest format" {
    // Verify the JSON-RPC message format by testing the string building logic
    const id: u32 = 42;
    const method = "tools/list";
    const params = "{

test "extractMcpSessionIdFromHeaders parses CRLF headers" {
    const hdr = "HTTP/2 200\r\ncontent-type: application/json\r\nmcp-session-id: abc123\r\ncache-control: no-cache\r\n";
    const got = McpServer.extractMcpSessionIdFromHeaders(hdr) orelse return error.TestExpectedEqual;

test "extractMcpSessionIdFromHeaders parses LF headers" {
    const hdr = "HTTP/1.1 200 OK\nMCP-Session-Id: zzz\nX: y\n";
    const got = McpServer.extractMcpSessionIdFromHeaders(hdr) orelse return error.TestExpectedEqual;
