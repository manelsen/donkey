//! Web Search Tool — internet search across multiple providers.
//!
//! Supported providers:
//!   - searxng
//!   - duckduckgo (ddg)
//!   - brave
//!   - firecrawl
//!   - tavily
//!   - perplexity
//!   - exa
//!   - jina
//!
//! Provider selection:
//! 1) `provider = "auto"` (default): tries a built-in chain.
//! 2) Explicit provider via config (`http_request.search_provider`) or tool arg (`provider`).
//! 3) Optional fallback chain (`http_request.search_fallback_providers`).

const std = @import("std");
const root = @import("root.zig");
const platform = @import("../platform.zig");
const search_providers = @import("web_search_providers/root.zig");
const search_common = search_providers.common;
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

/// Maximum number of search results.
const MAX_RESULTS: usize = 10;
/// Default number of search results.
const DEFAULT_COUNT: usize = 5;
/// Default request timeout for backend HTTP calls.
const DEFAULT_TIMEOUT_SECS: u64 = 30;
/// Upper bound for provider chain size (primary + fallbacks + auto expansions).
const MAX_PROVIDER_CHAIN: usize = 16;

const SearchProvider = enum {

const ProviderSearchError = search_common.ProviderSearchError;

/// Web search tool supporting multiple providers.
pub const WebSearchTool = struct {
    /// Optional SearXNG base URL (HTTPS anywhere, or local/private HTTP).
    /// Primary provider ("auto" by default).
    /// Fallback providers tried in order when primary fails.

fn parseProvider(raw: []const u8) ?SearchProvider

fn providerName(provider: SearchProvider) []const u8

fn appendProviderUnique(chain: []SearchProvider, len: *usize, provider: SearchProvider) void

    var len: usize = 0;

    const primary = parseProvider(primary_raw) orelse return error.InvalidProvider;

        const fallback = parseProvider(raw) orelse return error.InvalidProvider;


            const base_url = self.searxng_base_url orelse return error.ProviderUnavailable;
            const trimmed = std.mem.trim(u8, base_url, " \t\n\r");
            const api_key = tryApiKeyFromEnvOrNull(allocator, &.{
            const api_key = tryApiKeyFromEnvOrNull(allocator, &.{
            const api_key = tryApiKeyFromEnvOrNull(allocator, &.{
            const api_key = tryApiKeyFromEnvOrNull(allocator, &.{
            const api_key = tryApiKeyFromEnvOrNull(allocator, &.{
            const api_key = tryApiKeyFromEnvOrNull(allocator, &.{

fn tryApiKeyFromEnvOrNull(allocator: std.mem.Allocator, names: []const []const u8) ?[]const u8

fn parseCount(args: JsonObjectMap) usize

pub fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8

fn urlEncodePath(allocator: std.mem.Allocator, input: []const u8) ![]u8


pub fn formatBraveResults(allocator: std.mem.Allocator, json_body: []const u8, query: []const u8) !ToolResult

pub fn formatSearxngResults(allocator: std.mem.Allocator, json_body: []const u8, query: []const u8) !ToolResult

fn formatDuckDuckGoResults(allocator: std.mem.Allocator, json_body: []const u8, query: []const u8, count: usize) !ToolResult

// ══════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════

const testing = std.testing;

test "WebSearchTool name and description" {
    var wst = WebSearchTool{