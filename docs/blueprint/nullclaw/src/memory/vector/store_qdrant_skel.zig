//! QdrantVectorStore — VectorStore vtable adapter for Qdrant REST API.
//!
//! Implements the VectorStore interface by sending HTTP requests to a
//! running Qdrant instance. Supports upsert, search, delete, count,
//! and healthCheck via the Qdrant REST endpoints.

const std = @import("std");
const Allocator = std.mem.Allocator;
const store_mod = @import("store.zig");
const VectorStore = store_mod.VectorStore;
const VectorResult = store_mod.VectorResult;
const HealthStatus = store_mod.HealthStatus;
const appendJsonEscaped = @import("../../util.zig").appendJsonEscaped;
const net_security = @import("../../net_security.zig");

// ── Config ────────────────────────────────────────────────────────

pub const QdrantConfig = struct {

// ── QdrantVectorStore ─────────────────────────────────────────────

pub const QdrantVectorStore = struct {
    /// Validate that a collection name is safe for URL interpolation.
    /// Qdrant collection names must be alphanumeric, underscore, or hyphen.

// ── Tests ─────────────────────────────────────────────────────────

test "QdrantVectorStore init and deinit" {
    // Verify fields are duped (not pointers to stack memory)

test "QdrantVectorStore init without api_key" {

test "QdrantVectorStore rejects insecure remote http url" {

test "QdrantVectorStore accepts https remote url" {

test "QdrantVectorStore produces valid VectorStore vtable" {
    const s = q.store();
    // Verify the vtable is wired correctly (methods are non-null function pointers)

test "buildUpsertPayload generates valid JSON" {
    const alloc = std.testing.allocator;
    const embedding = [_]f32{

test "buildUpsertPayload escapes special characters" {
    const alloc = std.testing.allocator;
    const embedding = [_]f32{

test "buildSearchPayload generates valid JSON" {
    const alloc = std.testing.allocator;
    const query = [_]f32{

test "buildDeletePayload generates valid JSON" {
    const alloc = std.testing.allocator;
    const payload = try QdrantVectorStore.buildDeletePayload(alloc, "my_key");

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{

test "parseSearchResults valid response" {
    const alloc = std.testing.allocator;

    const results = try QdrantVectorStore.parseSearchResults(alloc, json);


test "parseSearchResults empty result" {
    const alloc = std.testing.allocator;

    const results = try QdrantVectorStore.parseSearchResults(alloc, json);


test "parseSearchResults invalid JSON returns error" {
    const alloc = std.testing.allocator;
    const result = QdrantVectorStore.parseSearchResults(alloc, "not json");

test "parseSearchResults missing result field returns error" {
    const alloc = std.testing.allocator;
    const result = QdrantVectorStore.parseSearchResults(alloc, json);

test "parseCountResult valid response" {
    const alloc = std.testing.allocator;

    const count = try QdrantVectorStore.parseCountResult(alloc, json);

test "parseCountResult zero count" {
    const alloc = std.testing.allocator;

    const count = try QdrantVectorStore.parseCountResult(alloc, json);

test "parseCountResult invalid JSON returns error" {
    const alloc = std.testing.allocator;
    const result = QdrantVectorStore.parseCountResult(alloc, "bad");

test "parseCountResult missing count field returns error" {
    const alloc = std.testing.allocator;
    const result = QdrantVectorStore.parseCountResult(alloc, json);

test "appendJsonEscaped handles special characters" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;



test "appendJsonEscaped handles plain text" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;



test "buildUrl constructs correct endpoint" {

    const url = try q.buildUrl(std.testing.allocator, "/points/search");


test "buildUrl with empty path" {

    const url = try q.buildUrl(std.testing.allocator, "");


test "keyToUuid produces valid UUID format" {
    const uuid = QdrantVectorStore.keyToUuid("test_key");
    // Check dash positions
    // Check version nibble (position 14) is '5'
    // Check variant nibble (position 19) is 8, 9, a, or b

test "keyToUuid is deterministic" {
    const uuid_a = QdrantVectorStore.keyToUuid("hello");
    const uuid_b = QdrantVectorStore.keyToUuid("hello");

test "keyToUuid differs for different keys" {
    const uuid_a = QdrantVectorStore.keyToUuid("alpha");
    const uuid_b = QdrantVectorStore.keyToUuid("beta");

// ── R3 tests ──────────────────────────────────────────────────────

test "buildUpsertPayload rejects NaN embedding" {
    const alloc = std.testing.allocator;
    const embedding = [_]f32{

test "buildUpsertPayload rejects Inf embedding" {
    const alloc = std.testing.allocator;
    const embedding = [_]f32{

test "buildSearchPayload rejects NaN query" {
    const alloc = std.testing.allocator;
    const query = [_]f32{

test "validateCollectionName rejects invalid names" {

test "validateCollectionName accepts valid names" {

test "QdrantVectorStore init rejects bad collection name" {
