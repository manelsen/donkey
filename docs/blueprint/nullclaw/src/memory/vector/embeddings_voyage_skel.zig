//! Voyage AI embedding provider — voyage-3-lite via /v1/embeddings API.
//!
//! API: POST https://api.voyageai.com/v1/embeddings
//! Auth: Bearer token in Authorization header
//! Default model: "voyage-3-lite", 512 dimensions
//! Note: input_type matters — "query" for search, "document" for storage.

const std = @import("std");
const EmbeddingProvider = @import("embeddings.zig").EmbeddingProvider;
const appendJsonEscaped = @import("../../util.zig").appendJsonEscaped;

pub const VoyageEmbedding = struct {

/// Parse Voyage response: {"data":[{"embedding":[0.1, 0.2, ...]}]}
pub fn parseVoyageResponse(allocator: std.mem.Allocator, json_bytes: []const u8) ![]f32

// ── Tests ─────────────────────────────────────────────────────────

test "VoyageEmbedding init and deinit" {
    const p = impl_.provider();

test "VoyageEmbedding init with custom values" {
    const p = impl_.provider();

test "VoyageEmbedding embed empty text" {
    const p = impl_.provider();

    const vec = try p.embed(std.testing.allocator, "");

test "VoyageEmbedding buildRequestBody query" {
    const body = try VoyageEmbedding.buildRequestBody(std.testing.allocator, "voyage-3-lite", "hello world", "query");

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "VoyageEmbedding buildRequestBody document" {
    const body = try VoyageEmbedding.buildRequestBody(std.testing.allocator, "voyage-3-lite", "some document", "document");

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "VoyageEmbedding buildRequestBody escapes special chars" {
    const body = try VoyageEmbedding.buildRequestBody(std.testing.allocator, "model", "hello \"world\"\nnewline", "query");

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "parseVoyageResponse valid" {
    const result = try parseVoyageResponse(std.testing.allocator, json);


test "parseVoyageResponse empty data" {
    const result = parseVoyageResponse(std.testing.allocator, json);

test "parseVoyageResponse missing data" {
    const result = parseVoyageResponse(std.testing.allocator, json);

test "parseVoyageResponse integer values" {
    const result = try parseVoyageResponse(std.testing.allocator, json);

// ── R3 regression tests ───────────────────────────────────────────

test "parseVoyageResponse string value returns error" {
    const result = parseVoyageResponse(std.testing.allocator, json);

test "parseVoyageResponse null value returns error" {
    const result = parseVoyageResponse(std.testing.allocator, json);

test "parseVoyageResponse root is array returns error" {
    const result = parseVoyageResponse(std.testing.allocator, json);

test "buildRequestBody model with quotes is properly escaped" {
    const body = try VoyageEmbedding.buildRequestBody(std.testing.allocator, "model\"evil", "test", "query");

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{
