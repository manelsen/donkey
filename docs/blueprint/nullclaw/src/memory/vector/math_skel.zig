//! Vector operations — cosine similarity, normalization, hybrid merge.
//!
//! Mirrors ZeroClaw's vector module for semantic search support.

const std = @import("std");

// ── Cosine similarity ─────────────────────────────────────────────

/// Cosine similarity between two vectors. Returns 0.0–1.0.
/// Returns 0.0 for empty, mismatched, or degenerate inputs.
pub fn cosineSimilarity(a: []const f32, b: []const f32) f32

// ── Serialization ─────────────────────────────────────────────────

/// Serialize f32 vector to bytes (little-endian). Caller owns result.
pub fn vecToBytes(allocator: std.mem.Allocator, v: []const f32) ![]u8

/// Deserialize bytes to f32 vector (little-endian). Caller owns result.
pub fn bytesToVec(allocator: std.mem.Allocator, bytes: []const u8) ![]f32

// ── Scored result ─────────────────────────────────────────────────

pub const ScoredResult = struct {

// ── Hybrid merge ──────────────────────────────────────────────────

pub const IdScore = struct {

/// Hybrid merge: combine vector and keyword results with weighted fusion.
///
/// Normalizes keyword scores to [0, 1]. Vector scores (cosine similarity)
/// are assumed to already be in [0, 1].
///
/// final_score = vector_weight * vector_score + keyword_weight * keyword_score
///
/// Deduplicates by id. Results sorted by final_score descending.
/// Caller owns the returned slice and must free it.
    // Use a simple approach: collect all unique ids, track scores
    var ids: std.ArrayList([]const u8) = .empty;

    var vec_scores = std.StringHashMap(f32).init(allocator);

    var kw_scores = std.StringHashMap(f32).init(allocator);

        const entry = try vec_scores.getOrPut(vr.id);
            // Keep best score

    // Normalize keyword scores
    var max_kw: f32 = 0.0;

        const normalized = kr.score / max_kw;
        const entry = try kw_scores.getOrPut(kr.id);
            // Check if this id already exists in vector results

    // Build scored results
    var results: std.ArrayList(ScoredResult) = .empty;

        const vs = vec_scores.get(id);
        const ks = kw_scores.get(id);
        const vs_val = vs orelse 0.0;
        const ks_val = ks orelse 0.0;
        const final = vector_weight * vs_val + keyword_weight * ks_val;

    // Sort by final_score descending
        fn lessThan(_: void, lhs: ScoredResult, rhs: ScoredResult) bool

    // Truncate to limit
    const actual_limit = @min(limit, results.items.len);

// ── Tests ─────────────────────────────────────────────────────────

test "cosine identical vectors" {
    const v = [_]f32{

test "cosine orthogonal vectors" {
    const a = [_]f32{

test "cosine similar vectors" {
    const a = [_]f32{

test "cosine empty returns zero" {
    const empty: []const f32 = &.{

test "cosine mismatched lengths" {
    const a = [_]f32{

test "cosine zero vector" {
    const a = [_]f32{

test "cosine opposite vectors clamped to zero" {
    const a = [_]f32{

test "cosine both zero vectors" {
    const a = [_]f32{

test "cosine single element" {
    const a = [_]f32{

test "vec bytes roundtrip" {
    const original = [_]f32{

test "vec bytes empty" {
    const empty: []const f32 = &.{

test "bytes to vec non-aligned truncates" {
    // 5 bytes -> only first 4 used (1 float), last byte dropped
    const bytes = [_]u8{

test "bytes to vec three bytes returns empty" {
    const bytes = [_]u8{

test "hybrid merge vector only" {
    const merged = try hybridMerge(std.testing.allocator, &vec_results, &.{

test "hybrid merge keyword only" {
    const merged = try hybridMerge(std.testing.allocator, &.{

test "hybrid merge deduplicates" {
    const merged = try hybridMerge(std.testing.allocator, &vec_results, &kw_results, 0.7, 0.3, 10);

    // Final score should be higher than vector alone

test "hybrid merge respects limit" {
    var vec_results: [20]IdScore = undefined;
    var id_bufs: [20][8]u8 = undefined;
        const id = std.fmt.bufPrint(&id_bufs[i], "item_{
    const merged = try hybridMerge(std.testing.allocator, &vec_results, &.{

test "hybrid merge empty inputs" {
    const merged = try hybridMerge(std.testing.allocator, &.{

test "hybrid merge limit zero" {
    const merged = try hybridMerge(std.testing.allocator, &vec_results, &.{

test "hybrid merge zero weights" {
    const merged = try hybridMerge(std.testing.allocator, &vec_results, &kw_results, 0.0, 0.0, 10);

// ── R3 regression tests ───────────────────────────────────────────

test "cosine zero vector returns 0.0 r3" {
    const zero = [_]f32{

test "cosine identical vectors returns 1.0 r3" {
    const v = [_]f32{

test "cosine orthogonal vectors returns 0.0 r3" {
    const a = [_]f32{

test "cosine NaN in vector returns 0.0 not NaN" {
    const a = [_]f32{

test "cosine inf in vector returns 0.0" {
    const a = [_]f32{
