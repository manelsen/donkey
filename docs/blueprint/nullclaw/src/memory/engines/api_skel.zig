//! HTTP API Memory backend — delegates to an external REST service.
//!
//! Implements the Memory + SessionStore vtable interfaces by sending
//! HTTP requests to a user-provided REST API server.
//! Pattern follows store_qdrant.zig: std.http.Client + std.Io.Writer.Allocating.

const std = @import("std");
const Allocator = std.mem.Allocator;
const appendJsonEscaped = @import("../../util.zig").appendJsonEscaped;
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;
const MessageEntry = root.MessageEntry;
const SessionInfo = root.SessionInfo;
const SessionStore = root.SessionStore;
const DetailedMessageEntry = root.DetailedMessageEntry;
const config_types = @import("../../config_types.zig");
const net_security = @import("../../net_security.zig");
const url_percent = @import("../../url_percent.zig");
const log = std.log.scoped(.api_memory);

// ── ApiMemory ─────────────────────────────────────────────────────

pub const ApiMemory = struct {

// ── Tests ─────────────────────────────────────────────────────────

test "api memory name" {
    var mem = try ApiMemory.init(std.testing.allocator, .{

test "api memory health url building" {

    const url = try mem.buildHealthUrl(std.testing.allocator);

test "api memory init/deinit" {
    // Empty URL is invalid for API backend

    // With URL and api_key


test "api init rejects insecure remote http url" {

test "api init accepts https remote url" {

test "api url building" {

    // Memory URL with key
    const url1 = try mem.buildMemoryUrl(std.testing.allocator, "my_key");

    // Memory URL without key
    const url2 = try mem.buildMemoryUrl(std.testing.allocator, null);

    // Search URL
    const url3 = try mem.buildSearchUrl(std.testing.allocator);

    // Count URL
    const url4 = try mem.buildCountUrl(std.testing.allocator);

    // Health URL
    const url5 = try mem.buildHealthUrl(std.testing.allocator);

    // Session messages URL
    const url6 = try mem.buildSessionMessagesUrl(std.testing.allocator, "sess-42");

    // Session usage URL
    const url7 = try mem.buildSessionUsageUrl(std.testing.allocator, "sess-42");

    // History list URL
    const url8 = try mem.buildHistoryListUrl(std.testing.allocator, 50, 10);

    // History show URL
    const url9 = try mem.buildHistoryShowUrl(std.testing.allocator, "sess-42", 100, 20);

test "api url building with trailing slash" {


test "api url building no namespace" {

    const url = try mem.buildMemoryUrl(std.testing.allocator, "key1");

test "api url building list with query params" {

    // Both params
    const url1 = try mem.buildMemoryUrlWithQuery(std.testing.allocator, "core", "sess-1");

    // Category only
    const url2 = try mem.buildMemoryUrlWithQuery(std.testing.allocator, "daily", null);

    // Session only
    const url3 = try mem.buildMemoryUrlWithQuery(std.testing.allocator, null, "sess-2");

    // Neither
    const url4 = try mem.buildMemoryUrlWithQuery(std.testing.allocator, null, null);

test "api json escaping" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


test "api json escaping control chars" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;

    // Test null byte and other control characters

test "api json escaping plain text" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


test "api parse entries" {
    const alloc = std.testing.allocator;

    const entries = try ApiMemory.parseEntries(alloc, json);




test "api parse entries empty" {
    const alloc = std.testing.allocator;

    const entries = try ApiMemory.parseEntries(alloc, json);


test "api parse entries invalid json" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseEntries(alloc, "not json");

test "api parse entries missing field" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseEntries(alloc, json);

test "api parse messages" {
    const alloc = std.testing.allocator;

    const messages = try ApiMemory.parseMessages(alloc, json);


test "api parse messages empty" {
    const alloc = std.testing.allocator;

    const messages = try ApiMemory.parseMessages(alloc, json);


test "api parse messages invalid json" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseMessages(alloc, "bad");

test "api parse usage" {
    const alloc = std.testing.allocator;
    const total = try ApiMemory.parseUsage(alloc, json);

test "api parse usage accepts string" {
    const alloc = std.testing.allocator;
    const total = try ApiMemory.parseUsage(alloc, json);

test "api parse usage null" {
    const alloc = std.testing.allocator;
    const total = try ApiMemory.parseUsage(alloc, json);

test "api parse usage invalid" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseUsage(alloc, "{

test "api parse history list response" {
    const alloc = std.testing.allocator;

    var parsed = try ApiMemory.parseHistoryListResponse(alloc, json);


test "api parse history show response" {
    const alloc = std.testing.allocator;

    var parsed = try ApiMemory.parseHistoryShowResponse(alloc, json);


test "api parse history list response invalid" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseHistoryListResponse(alloc, "{

test "api parse history show response invalid" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseHistoryShowResponse(alloc, "{

test "api parse count" {
    const alloc = std.testing.allocator;
    const count = try ApiMemory.parseCount(alloc, json);

test "api parse count zero" {
    const alloc = std.testing.allocator;
    const count = try ApiMemory.parseCount(alloc, json);

test "api parse count invalid" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseCount(alloc, "bad");

test "api parse count missing field" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseCount(alloc, json);

test "api parse curl output with body" {
    const parsed = try ApiMemory.parseCurlOutput(std.testing.allocator, out);

test "api parse curl output with empty body" {
    const parsed = try ApiMemory.parseCurlOutput(std.testing.allocator, out);

test "api build store payload" {
    const alloc = std.testing.allocator;
    const payload = try ApiMemory.buildStorePayload(alloc, "dark theme", .core, null);

    // Validate it's valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{

test "api build store payload with session" {
    const alloc = std.testing.allocator;
    const payload = try ApiMemory.buildStorePayload(alloc, "content", .daily, "sess-1");

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{

test "api build search payload" {
    const alloc = std.testing.allocator;
    const payload = try ApiMemory.buildSearchPayload(alloc, "search query", 5, null);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{

test "api build message payload" {
    const alloc = std.testing.allocator;
    const payload = try ApiMemory.buildMessagePayload(alloc, "user", "Hello world");

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{

test "api build usage payload" {
    const alloc = std.testing.allocator;
    const payload = try ApiMemory.buildUsagePayload(alloc, 321);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{

test "api memory produces vtable" {
    var mem = try ApiMemory.init(std.testing.allocator, .{

test "api memory produces session store vtable" {
    var mem = try ApiMemory.init(std.testing.allocator, .{

test "api memory no session store when disabled" {
    var mem = try ApiMemory.init(std.testing.allocator, .{

test "api init with empty api_key" {


test "api parse single entry" {
    const alloc = std.testing.allocator;

    const entry = try ApiMemory.parseSingleEntry(alloc, json) orelse return error.TestUnexpectedResult;


test "api parse entries with custom category" {
    const alloc = std.testing.allocator;

    const entries = try ApiMemory.parseEntries(alloc, json);


test "api namespace without leading slash" {

test "api namespace with trailing slash" {

test "api url encoding in path" {
    const alloc = std.testing.allocator;
    var mem = try ApiMemory.init(alloc, .{

test "api url encoding in query params" {
    const alloc = std.testing.allocator;
    var mem = try ApiMemory.init(alloc, .{

test "api url encoding preserves safe chars" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;


test "api parse count rejects negative" {
    const alloc = std.testing.allocator;
    const result = ApiMemory.parseCount(alloc, json);
