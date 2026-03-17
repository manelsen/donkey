const std = @import("std");
const appendJsonEscaped = @import("../util.zig").appendJsonEscaped;
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

const COMPOSIO_API_BASE_V2 = "https://backend.composio.dev/api/v2";
const COMPOSIO_API_BASE_V3 = "https://backend.composio.dev/api/v3";

/// Composio tool — proxy actions to the Composio managed tool platform.
/// Supports 1000+ OAuth integrations (Gmail, Notion, GitHub, Slack, etc.).
/// Operations: list (available actions), execute (run an action), connect (get OAuth URL).
/// Uses v3 API endpoints with v2 fallback for compatibility.
pub const ComposioTool = struct {

// ── Helper functions ────────────────────────────────────────────────

/// Convert UPPER_SNAKE_CASE to kebab-case: GMAIL_FETCH_EMAILS -> gmail-fetch-emails
pub fn normalizeToolSlug(allocator: std.mem.Allocator, name: []const u8) ![]const u8

/// Normalize entity ID: trim whitespace, default to "default" if empty.
pub fn normalizeEntityId(entity_id: ?[]const u8) []const u8

/// Sanitize error message: redact potential secrets (long alphanumeric strings > 20 chars)
/// and truncate to 240 chars.
pub fn sanitizeErrorMessage(allocator: std.mem.Allocator, msg: []const u8) ![]const u8

/// Extract error message from JSON response body.
/// Tries {"error":{"message":"..."}} then {"message":"..."}.
pub fn extractApiErrorMessage(allocator: std.mem.Allocator, body: []const u8) !?[]const u8

// ── Tests ───────────────────────────────────────────────────────────

test "composio tool name" {
    var ct = ComposioTool{

test "composio tool schema has action" {
    var ct = ComposioTool{

test "composio missing action returns error" {
    var ct = ComposioTool{

test "composio unknown action returns error" {
    var ct = ComposioTool{

test "composio no api key returns error" {
    var ct = ComposioTool{

test "composio list action invokes curl" {
    var ct = ComposioTool{

test "composio list with app filter invokes curl" {
    var ct = ComposioTool{

test "composio execute missing action_name" {
    var ct = ComposioTool{

test "composio execute with action_name invokes curl" {
    var ct = ComposioTool{

test "composio connect missing app" {
    var ct = ComposioTool{

test "composio connect with app invokes curl" {
    var ct = ComposioTool{

// ── v3 helper tests ─────────────────────────────────────────────────

test "composio v3 api base url" {

test "composio normalizeToolSlug converts UPPER_SNAKE to kebab" {
    const alloc = std.testing.allocator;
    const result = try normalizeToolSlug(alloc, "GMAIL_FETCH_EMAILS");

test "composio normalizeToolSlug handles already lowercase" {
    const alloc = std.testing.allocator;
    const result = try normalizeToolSlug(alloc, "github-list-repos");

test "composio normalizeEntityId defaults to default" {

test "composio normalizeEntityId trims whitespace" {

test "composio extractApiErrorMessage parses message format" {
    const alloc = std.testing.allocator;
    const result = try extractApiErrorMessage(alloc, "{

test "composio extractApiErrorMessage parses nested error format" {
    const alloc = std.testing.allocator;
    const result = try extractApiErrorMessage(alloc, "{

test "composio extractApiErrorMessage returns null for non-json" {
    const alloc = std.testing.allocator;
    const result = try extractApiErrorMessage(alloc, "not-json-at-all");

test "composio sanitizeErrorMessage truncates at 240 chars" {
    const alloc = std.testing.allocator;
    // Build a message longer than 240 chars using short words (< 20 chars each)
    // so they won't be redacted. "word " is 5 chars, 60 * 5 = 300 chars.
    const long_msg = "word " ** 60;
    const result = try sanitizeErrorMessage(alloc, long_msg);
