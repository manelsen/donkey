//! Ollama local embedding provider — nomic-embed-text via /api/embed endpoint.
//!
//! API: POST http://localhost:11434/api/embed
//! Auth: none (local service)
//! Default model: "nomic-embed-text", 768 dimensions (model-dependent)

const std = @import("std");
const EmbeddingProvider = @import("embeddings.zig").EmbeddingProvider;
const appendJsonEscaped = @import("../../util.zig").appendJsonEscaped;
const net_security = @import("../../net_security.zig");

pub const OllamaEmbedding = struct {

/// Parse Ollama response: {"embeddings":[[0.1, 0.2, ...]]}
pub fn parseOllamaResponse(allocator: std.mem.Allocator, json_bytes: []const u8) ![]f32

// ── Tests ─────────────────────────────────────────────────────────

test "OllamaEmbedding init and deinit" {
    const p = impl_.provider();

test "OllamaEmbedding init with custom values" {
    const p = impl_.provider();

test "OllamaEmbedding init rejects insecure remote http url" {

test "OllamaEmbedding embed empty text" {
    const p = impl_.provider();

    const vec = try p.embed(std.testing.allocator, "");

test "OllamaEmbedding buildRequestBody" {
    const body = try OllamaEmbedding.buildRequestBody(std.testing.allocator, "nomic-embed-text", "hello world");

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "OllamaEmbedding buildRequestBody escapes special chars" {
    const body = try OllamaEmbedding.buildRequestBody(std.testing.allocator, "model", "hello \"world\"\nnewline");

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "parseOllamaResponse valid" {
    const result = try parseOllamaResponse(std.testing.allocator, json);


test "parseOllamaResponse empty outer array" {
    const result = parseOllamaResponse(std.testing.allocator, json);

test "parseOllamaResponse missing embeddings" {
    const result = parseOllamaResponse(std.testing.allocator, json);

test "parseOllamaResponse integer values" {
    const result = try parseOllamaResponse(std.testing.allocator, json);

test "parseOllamaResponse empty inner array" {
    const result = try parseOllamaResponse(std.testing.allocator, json);

// ── R3 regression tests ───────────────────────────────────────────

test "parseOllamaResponse string value returns error" {
    const result = parseOllamaResponse(std.testing.allocator, json);

test "parseOllamaResponse null value returns error" {
    const result = parseOllamaResponse(std.testing.allocator, json);

test "parseOllamaResponse root is array returns error" {
    const result = parseOllamaResponse(std.testing.allocator, json);

test "buildRequestBody model with quotes is properly escaped" {
    const body = try OllamaEmbedding.buildRequestBody(std.testing.allocator, "model\"evil", "test");

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{
