//! LLM reranker — post-processing stage that uses an LLM to rerank
//! retrieval candidates by relevance to the query.
//!
//! This module is a PURE reranking stage: it builds prompts, parses responses,
//! and reorders candidates.  It does NOT make LLM calls itself — the caller
//! is responsible for invoking the LLM and passing the response back.
//!
//! Pipeline position:
//!   keyword → vector → RRF → min_relevance → temporal_decay → MMR → LLM_rerank → limit

const std = @import("std");
const Allocator = std.mem.Allocator;
const retrieval = @import("engine.zig");
const RetrievalCandidate = retrieval.RetrievalCandidate;

// ── Config ───────────────────────────────────────────────────────

pub const LlmRerankerConfig = struct {

// ── Result ───────────────────────────────────────────────────────

pub const RerankerResult = struct {

// ── Prompt building ──────────────────────────────────────────────

const snippet_max_len: usize = 200;

/// Build the reranking prompt for the LLM.
///
/// Format:
///   Given the query: '{query}', rank the following items by relevance.
///   Return ONLY the indices in order of relevance, e.g.: 3,1,5,2,4
///
///   1. {candidate1.content[:200]}
///   2. {candidate2.content[:200]}
///   ...
    const limit = @min(candidates.len, @as(usize, max_candidates));

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = buf.writer(allocator);


        // Sanitize: replace newlines to prevent prompt structure manipulation
        var sanitized: [snippet_max_len]u8 = undefined;
        const slen = @min(snippet.len, snippet_max_len);


// ── Response parsing ─────────────────────────────────────────────

/// Parse the LLM response to extract ranking order.
///
/// Accepted formats:
///   "3,1,5,2,4"       — comma-separated
///   "3, 1, 5, 2, 4"   — with spaces
///   "3\n1\n5\n2\n4"   — newline-separated
///
/// Returns 1-based indices in ranked order.
/// Falls back to original order (1,2,...,N) on parse failure, duplicates,
/// or out-of-range indices.

    // Try to parse indices from the response
    var indices: std.ArrayListUnmanaged(usize) = .empty;

    // Split on commas first; if that yields only 1 token, try newlines
    var parsed_any = false;
    var comma_failed = false;
    var comma_iter = std.mem.splitScalar(u8, response, ',');
        const trimmed = std.mem.trim(u8, token, " \t\r\n");
            // Token not a number — comma split didn't work, try newlines

    // If comma split failed or gave us only 1 result but we have multiple
    // candidates, try newline split instead
        var nl_iter = std.mem.splitScalar(u8, response, '\n');
            const trimmed = std.mem.trim(u8, token, " \t\r,");


    // Validate: all indices must be in [1, candidate_count] and unique
    var seen = try allocator.alloc(bool, candidate_count);

            // Duplicate

    // Valid — return owned slice

/// Generate the fallback order: [1, 2, 3, ..., N]
fn fallbackOrder(allocator: Allocator, count: usize) ![]usize

// ── Reordering ───────────────────────────────────────────────────

/// Reorder candidates according to the LLM's ranking.
///
/// `ranking` contains 1-based indices in the desired order.
/// Returns a new slice; the original candidates slice is NOT freed.
/// Candidates not mentioned in `ranking` are appended at the end
/// in their original order.

    var result = try allocator.alloc(RetrievalCandidate, candidates.len);

    // Track which candidates have been placed
    var placed = try allocator.alloc(bool, candidates.len);

    var out_idx: usize = 0;

    // First: add candidates in the ranking order
        const src_idx = rank_idx - 1;

    // Then: append any unranked candidates in original order


// ── Tests ────────────────────────────────────────────────────────

fn makeCandidate(comptime id_suffix: u8, content: []const u8, score: f64) RetrievalCandidate

test "buildRerankPrompt correctly formats prompt with query and candidates" {
    const allocator = std.testing.allocator;

    const prompt = try buildRerankPrompt(allocator, "test query", &candidates, 10);

    try std.testing.expect(std.mem.indexOf(u8, prompt, "test query") != null);

test "buildRerankPrompt truncates long content at 200 chars" {
    const allocator = std.testing.allocator;
    const long_content = "A" ** 300;

    const prompt = try buildRerankPrompt(allocator, "q", &candidates, 10);

    // Should contain the truncated version (200 A's), not the full 300
    const expected_snippet = "A" ** 200;
    // And not 201 A's in a row
    const too_long = "A" ** 201;

test "buildRerankPrompt respects max_candidates limit" {
    const allocator = std.testing.allocator;

    const prompt = try buildRerankPrompt(allocator, "q", &candidates, 2);

    // Items 3 and 4 should NOT appear

test "parseRerankResponse comma separated" {
    const allocator = std.testing.allocator;
    const result = try parseRerankResponse(allocator, "3,1,2", 3);


test "parseRerankResponse with spaces" {
    const allocator = std.testing.allocator;
    const result = try parseRerankResponse(allocator, "3, 1, 2", 3);


test "parseRerankResponse newline separated" {
    const allocator = std.testing.allocator;
    const result = try parseRerankResponse(allocator, "3\n1\n2", 3);


test "parseRerankResponse invalid input falls back to original order" {
    const allocator = std.testing.allocator;
    const result = try parseRerankResponse(allocator, "not a number at all", 3);


test "parseRerankResponse duplicate indices falls back" {
    const allocator = std.testing.allocator;
    const result = try parseRerankResponse(allocator, "1,1,2", 3);

    // Should fall back to [1,2,3]

test "parseRerankResponse out of range indices falls back" {
    const allocator = std.testing.allocator;
    const result = try parseRerankResponse(allocator, "1,5,2", 3);

    // 5 is out of range for 3 candidates → fallback

test "reorderCandidates correctly reorders by indices" {
    const allocator = std.testing.allocator;
    const ranking = [_]usize{

test "reorderCandidates preserves all candidate data" {
    const allocator = std.testing.allocator;
    const ranking = [_]usize{

test "reorderCandidates empty candidates is no-op" {
    const allocator = std.testing.allocator;
    const candidates = [_]RetrievalCandidate{

test "buildRerankPrompt empty candidates returns empty string" {
    const allocator = std.testing.allocator;
    const candidates = [_]RetrievalCandidate{

test "parseRerankResponse empty candidate_count returns empty" {
    const allocator = std.testing.allocator;
    const result = try parseRerankResponse(allocator, "1,2,3", 0);


test "parseRerankResponse empty response falls back to original order" {
    const allocator = std.testing.allocator;
    const result = try parseRerankResponse(allocator, "", 3);


test "parseRerankResponse partial ranking accepted" {
    const allocator = std.testing.allocator;
    // Only rank 2 out of 5 candidates — valid, the rest get appended
    const result = try parseRerankResponse(allocator, "3,1", 5);

    // Should succeed: partial rankings are valid

test "reorderCandidates partial ranking appends unranked at end" {
    const allocator = std.testing.allocator;
    // Only rank candidate 3 — the rest should follow in original order
    const ranking = [_]usize{

const MemoryCategory = @import("../root.zig").MemoryCategory;
