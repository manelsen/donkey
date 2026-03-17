//! Backend Registry — comptime descriptors for all memory backends.
//!
//! Each backend declares its name, capabilities, path requirements, and
//! factory function.  The path resolver (`resolvePaths`) centralises the
//! `joinZ` logic that was previously duplicated across 6 entry points.

const std = @import("std");
const build_options = @import("build_options");
const config_types = @import("../../config_types.zig");
const root = @import("../root.zig");
const memory_lru = @import("memory_lru.zig");
const redis_engine = @import("redis.zig");
const lancedb_engine = @import("lancedb.zig");
const api_engine = @import("api.zig");
const clickhouse_engine = @import("clickhouse.zig");

// ── Capability & descriptor types ────────────────────────────────

pub const BackendCapabilities = struct {

pub const BackendDescriptor = struct {

pub const BackendConfig = struct {

pub const BackendInstance = struct {

// ── Comptime registry ────────────────────────────────────────────




















pub const all = hybrid_backends ++ markdown_backends ++ api_backends ++ memory_backends ++ none_backends ++ sqlite_backends ++ lucid_backends ++ redis_backends ++ lancedb_backends ++ pg_backends ++ clickhouse_backends;
pub const known_backends_csv = "hybrid, none, markdown, memory, api, sqlite, lucid, redis, lancedb, postgres, clickhouse";

// ── Lookup ───────────────────────────────────────────────────────

pub fn findBackend(name: []const u8) ?*const BackendDescriptor

pub fn isKnownBackend(name: []const u8) bool

pub fn engineTokenForBackend(name: []const u8) ?[]const u8

pub fn formatEnabledBackends(allocator: std.mem.Allocator) ![]u8

// ── Path resolver ────────────────────────────────────────────────


    var pg_url: ?[*:0]const u8 = null;
    var pg_schema: []const u8 = "public";
    var pg_table: []const u8 = "memories";
    var pg_connect_timeout_secs: u32 = 30;


// ── Factory wrappers ─────────────────────────────────────────────

fn createHybrid(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance

fn createSqlite(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance

fn createMarkdown(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance

fn createLucid(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance

fn createMemoryLru(allocator: std.mem.Allocator, _: BackendConfig) !BackendInstance

fn createRedis(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance

fn createLanceDb(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance

fn createApi(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance

fn createNone(allocator: std.mem.Allocator, _: BackendConfig) !BackendInstance

fn createPostgres(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance

fn createClickHouse(allocator: std.mem.Allocator, cfg: BackendConfig) !BackendInstance


    // URI form: postgresql://... or postgres://...
        const sep: u8 = if (std.mem.indexOfScalar(u8, base_url, '?') != null) '&' else '?';
        const out = try std.fmt.allocPrint(allocator, "{

    // Keyword/value conninfo form.
    const out = try std.fmt.allocPrint(allocator, "{

// ── Tests ────────────────────────────────────────────────────────

test "registry length" {

test "findBackend sqlite" {
    const desc = findBackend("sqlite") orelse return error.TestUnexpectedResult;

test "findBackend markdown" {
    const desc = findBackend("markdown") orelse return error.TestUnexpectedResult;

test "findBackend memory" {
    const desc = findBackend("memory") orelse return error.TestUnexpectedResult;

test "findBackend lucid" {
    const desc = findBackend("lucid") orelse return error.TestUnexpectedResult;

test "findBackend none" {
    const desc = findBackend("none") orelse return error.TestUnexpectedResult;

test "findBackend redis" {
    const desc = findBackend("redis") orelse return error.TestUnexpectedResult;

test "findBackend lancedb" {
    const desc = findBackend("lancedb") orelse return error.TestUnexpectedResult;

test "findBackend api" {
    const desc = findBackend("api") orelse return error.TestUnexpectedResult;

test "findBackend clickhouse" {
    const desc = findBackend("clickhouse") orelse return error.TestUnexpectedResult;

test "findBackend unknown returns null" {

test "findBackend empty returns null" {

test "isKnownBackend validates canonical backend names" {

test "engineTokenForBackend maps known names and rejects unknown" {

test "formatEnabledBackends reflects compiled registry" {
    const rendered = try formatEnabledBackends(std.testing.allocator);


test "resolvePaths sqlite has db_path" {
    const desc = findBackend("sqlite") orelse return error.TestUnexpectedResult;
    const cfg = try resolvePaths(std.testing.allocator, desc, "/tmp/ws", null, null, null, null);

    const path_slice = std.mem.span(cfg.db_path.?);

test "resolvePaths markdown has no db_path" {
    const desc = findBackend("markdown") orelse return error.TestUnexpectedResult;
    const cfg = try resolvePaths(std.testing.allocator, desc, "/tmp/ws", null, null, null, null);


test "resolvePaths none has no db_path" {
    const desc = findBackend("none") orelse return error.TestUnexpectedResult;
    const cfg = try resolvePaths(std.testing.allocator, desc, "/tmp/ws", null, null, null, null);


test "createNone produces working memory" {


test "createNone returns session_store null" {


test "resolvePaths redis config is preserved" {
    const desc = findBackend("redis") orelse return error.TestUnexpectedResult;


test "applyPostgresConnectTimeout uri appends query parameter" {

test "applyPostgresConnectTimeout uri appends with ampersand" {

test "applyPostgresConnectTimeout keeps existing timeout unchanged" {
