const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

/// Maximum response body size for the "read" action (8 KB).
const MAX_READ_BYTES: usize = 8192;
/// Maximum raw fetch size passed to curl (64 KB, then truncated to MAX_READ_BYTES).
const MAX_FETCH_BYTES: usize = 65536;

/// Browser tool — opens URLs in the system browser and fetches page content.
/// Supports "open" (launch URL), "read" (fetch body via curl), and returns
/// informative errors for CDP-only actions (click, type, scroll, screenshot).
pub const BrowserTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "browser tool name" {
    var bt = BrowserTool{

test "browser open launches system browser" {
    var bt = BrowserTool{

test "browser open rejects http" {
    var bt = BrowserTool{

test "browser screenshot redirects to screenshot tool" {
    var bt = BrowserTool{

// ── Additional browser tests ────────────────────────────────────

test "browser missing action parameter" {
    var bt = BrowserTool{

test "browser open missing url" {
    var bt = BrowserTool{

test "browser click action requires CDP" {
    var bt = BrowserTool{

test "browser read missing url" {
    var bt = BrowserTool{

test "browser open returns output with URL" {
    var bt = BrowserTool{

test "browser schema has enum values" {
    var bt = BrowserTool{

test "browser description mentions browse" {
    var bt = BrowserTool{

test "browser tool schema has url" {
    var bt = BrowserTool{

test "browser tool schema has action" {
    var bt = BrowserTool{

test "browser tool execute with empty json" {
    var bt = BrowserTool{

test "browser open rejects URL with shell metacharacters on Windows" {
    // On Windows, cmd.exe /c start interprets metacharacters — they must be blocked.
    // On Unix, open/xdg-open uses execvp so metacharacters in argv are safe.
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var bt = BrowserTool{

test "browser open allows URL with query params on Unix" {
    // On Unix, & in query strings is safe (passed as argv to open/xdg-open).
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    var bt = BrowserTool{
