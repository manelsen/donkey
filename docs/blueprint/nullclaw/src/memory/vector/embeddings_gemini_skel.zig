//! Gemini embedding provider — Google's text-embedding-004 via embedContent API.
//!
//! API: POST https://generativelanguage.googleapis.com/v1beta/models/{model}:embedContent
//! Auth: API key as query param `?key={api_key}`
//! Default model: "text-embedding-004", 768 dimensions

const std = @import("std");
const EmbeddingProvider = @import("embeddings.zig").EmbeddingProvider;
const appendJsonEscaped = @import("../../util.zig").appendJsonEscaped;

pub const GeminiEmbedding = struct {

/// Parse Gemini response: {"embedding":{"values":[0.1, 0.2, ...]}}
pub fn parseGeminiResponse(allocator: std.mem.Allocator, json_bytes: []const u8) ![]f32

// ── Tests ─────────────────────────────────────────────────────────

test "GeminiEmbedding init and deinit" {
    const p = impl_.provider();

test "GeminiEmbedding init with custom values" {
    const p = impl_.provider();

test "GeminiEmbedding embed empty text" {
    const p = impl_.provider();

    const vec = try p.embed(std.testing.allocator, "");

test "GeminiEmbedding buildRequestBody" {
    const body = try GeminiEmbedding.buildRequestBody(std.testing.allocator, "text-embedding-004", "hello world");

    // Verify it's valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "GeminiEmbedding buildRequestBody escapes special chars" {
    const body = try GeminiEmbedding.buildRequestBody(std.testing.allocator, "model", "hello \"world\"\nnewline");

    // Verify it's valid JSON (escaped properly)
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "parseGeminiResponse valid" {
    const result = try parseGeminiResponse(std.testing.allocator, json);


test "parseGeminiResponse empty values" {
    const result = try parseGeminiResponse(std.testing.allocator, json);

test "parseGeminiResponse missing embedding" {
    const result = parseGeminiResponse(std.testing.allocator, json);

test "parseGeminiResponse missing values" {
    const result = parseGeminiResponse(std.testing.allocator, json);

test "parseGeminiResponse integer values" {
    const result = try parseGeminiResponse(std.testing.allocator, json);

// ── R3 regression tests ───────────────────────────────────────────

test "buildRequestBody model name with quotes is properly escaped" {
    const body = try GeminiEmbedding.buildRequestBody(std.testing.allocator, "model\"with\"quotes", "test text");

    // Must be valid JSON despite quotes in model name
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "parseGeminiResponse string value in values returns error" {
    const result = parseGeminiResponse(std.testing.allocator, json);

test "parseGeminiResponse null value in values returns error" {
    const result = parseGeminiResponse(std.testing.allocator, json);

test "parseGeminiResponse root is array returns error" {
    const result = parseGeminiResponse(std.testing.allocator, json);
