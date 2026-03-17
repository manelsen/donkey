//! MMR (Maximal Marginal Relevance) diversity reranking.
//!
//! Iteratively selects candidates that balance relevance to the query
//! with diversity from already-selected results.  Applied after temporal
//! decay and before final truncation.
//!
//! Formula:  MMR(d) = lambda * Rel(d) - (1 - lambda) * max_sim(d, S)
//!   where   Rel(d)      = normalized final_score
//!           max_sim(d,S) = max Jaccard similarity to any selected candidate
//!           lambda       = config parameter (0.7 default)

const std = @import("std");
const Allocator = std.mem.Allocator;
const retrieval = @import("engine.zig");
const RetrievalCandidate = retrieval.RetrievalCandidate;
const config_types = @import("../../config_types.zig");

pub const MmrConfig = config_types.MemoryMmrConfig;

// ── Jaccard similarity ──────────────────────────────────────────

/// Tokenize text by splitting on whitespace and lowercasing.
/// Returns a set of unique lowercase tokens.  Caller must call
/// `deinitTokenSet` when done.
fn tokenize(allocator: Allocator, text: []const u8) !std.StringHashMap(void)

fn insertToken(allocator: Allocator, set: *std.StringHashMap(void), raw: []const u8) !void

fn deinitTokenSet(allocator: Allocator, set: *std.StringHashMap(void)) void

/// Jaccard similarity between two text strings.
/// Tokenizes by whitespace, lowercases, computes |intersection|/|union|.
/// Both-empty → 0.0 (nothing in common).
pub fn jaccardSimilarity(allocator: Allocator, text_a: []const u8, text_b: []const u8) !f64

fn jaccardFromSets(set_a: *const std.StringHashMap(void), set_b: *const std.StringHashMap(void)) f64

// ── MMR reranking ────────────────────────────────────────────────

/// Apply MMR reranking to candidates.
/// Returns a new slice with candidates reordered by MMR selection.
/// Caller owns the returned slice (all strings are duped).

    const n = candidates.len;
    const result_len = @min(n, limit);

    // Pre-tokenize all candidates
    var token_sets = try allocator.alloc(std.StringHashMap(void), n);
    var tokenized_count: usize = 0;

    // Normalize scores to [0,1]
    var min_score: f64 = candidates[0].final_score;
    var max_score: f64 = candidates[0].final_score;
    const score_range = max_score - min_score;

    var normalized = try allocator.alloc(f64, n);

    // Track which candidates are selected / remaining
    var selected_indices = try allocator.alloc(usize, result_len);
    var is_selected = try allocator.alloc(bool, n);

    // Step 1: Select the candidate with highest final_score
    var best_idx: usize = 0;
    var selected_count: usize = 1;

    // Steps 2-4: Iterative MMR selection
        var best_mmr: f64 = -std.math.inf(f64);
        // Initialize to first unselected candidate to avoid re-selecting index 0


            // Compute max similarity to any already-selected candidate
            var max_sim: f64 = 0.0;
                const sim = jaccardFromSets(&token_sets[i], &token_sets[si]);

            const mmr_score = config.lambda * normalized[i] - (1.0 - config.lambda) * max_sim;



    // Build result with duped strings
    var result = try allocator.alloc(RetrievalCandidate, result_len);
    var duped: usize = 0;


/// Copy up to `limit` candidates with duped strings.
    const out_len = @min(candidates.len, limit);
    var result = try allocator.alloc(RetrievalCandidate, out_len);
    var duped: usize = 0;

/// Deep-copy a single RetrievalCandidate (all string fields duped).
fn dupeCandidate(allocator: Allocator, c: RetrievalCandidate) !RetrievalCandidate

// ── Tests ────────────────────────────────────────────────────────

const MemoryCategory = @import("../root.zig").MemoryCategory;

fn makeCandidate(comptime id_key: []const u8, comptime content: []const u8, score: f64) RetrievalCandidate

test "mmr: single candidate returned as-is" {
    const allocator = std.testing.allocator;
    const result = try applyMmr(allocator, &candidates, .{

test "mmr: two identical candidates — duplicate penalized" {
    const allocator = std.testing.allocator;
    const result = try applyMmr(allocator, &candidates, .{

test "mmr: two completely different candidates — both selected at high scores" {
    const allocator = std.testing.allocator;
    const result = try applyMmr(allocator, &candidates, .{

test "mmr: lambda=1.0 pure relevance order" {
    const allocator = std.testing.allocator;
    const result = try applyMmr(allocator, &candidates, .{

test "mmr: lambda=0.0 maximum diversity" {
    const allocator = std.testing.allocator;
    // A and B have identical content, C is different
    const result = try applyMmr(allocator, &candidates, .{

test "mmr: empty candidates returns empty" {
    const allocator = std.testing.allocator;
    const candidates = [_]RetrievalCandidate{

test "mmr: disabled config preserves original order" {
    const allocator = std.testing.allocator;
    const result = try applyMmr(allocator, &candidates, .{

test "jaccard: identical texts returns 1.0" {
    const allocator = std.testing.allocator;
    const sim = try jaccardSimilarity(allocator, "hello world foo", "hello world foo");

test "jaccard: completely different texts returns 0.0" {
    const allocator = std.testing.allocator;
    const sim = try jaccardSimilarity(allocator, "alpha beta gamma", "one two three");

test "jaccard: partial overlap" {
    const allocator = std.testing.allocator;
    // tokens A: {hello, world, foo} — 3 tokens
    // tokens B: {hello, world, bar} — 3 tokens
    // intersection = 2, union = 4 → 0.5
    const sim = try jaccardSimilarity(allocator, "hello world foo", "hello world bar");

test "jaccard: empty text returns 0.0" {
    const allocator = std.testing.allocator;
    const sim1 = try jaccardSimilarity(allocator, "", "hello");
    const sim2 = try jaccardSimilarity(allocator, "", "");

test "jaccard: case insensitive" {
    const allocator = std.testing.allocator;
    const sim = try jaccardSimilarity(allocator, "Hello World", "hello world");

test "mmr: limit less than candidates returns limited count" {
    const allocator = std.testing.allocator;
    const result = try applyMmr(allocator, &candidates, .{

test "mmr: preserves candidate data" {
    const allocator = std.testing.allocator;
            .content = "test content",
    const result = try applyMmr(allocator, &candidates, .{

test "mmr: diversity — A relevant, B=copy of A, C different selects A then C" {
    const allocator = std.testing.allocator;
    // lambda=0.3 → heavy diversity preference
    const result = try applyMmr(allocator, &candidates, .{
