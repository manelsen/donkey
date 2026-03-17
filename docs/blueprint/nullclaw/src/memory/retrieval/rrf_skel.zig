//! Reciprocal Rank Fusion — merges candidates from multiple ranked lists.
//!
//! Pure function, no I/O, no dependencies beyond retrieval types.
//! Formula: score = sum(1 / (rank_i + k)) across all source lists.

const std = @import("std");
const Allocator = std.mem.Allocator;
const retrieval = @import("engine.zig");
const RetrievalCandidate = retrieval.RetrievalCandidate;

/// Reciprocal Rank Fusion: score = sum(1 / (rank_i + k))
/// Merges candidates from multiple ranked lists by content identity (key).
/// Returns merged candidates sorted by final_score descending, truncated to limit.
/// Caller owns the returned slice; free with `retrieval.freeCandidates`.

    // Single source → passthrough (copy candidates, set final_score from rank)

    // Build map: key → (accumulated score, first-seen candidate index in `merged`)
    var score_map = std.StringHashMap(ScoreEntry).init(allocator);

    var merged = std.ArrayListUnmanaged(MergeItem){

const ScoreEntry = struct {

const MergeItem = struct {

fn compareByScoreDesc(_: void, a: MergeItem, b: MergeItem) bool

fn singleSourceCopy(allocator: Allocator, source: []const RetrievalCandidate, k: u32, limit: usize) ![]RetrievalCandidate

fn cloneCandidate(allocator: Allocator, src: RetrievalCandidate, final_score: f64) !RetrievalCandidate

// ── Tests ──────────────────────────────────────────────────────────

test "single source passthrough preserves order" {
    const allocator = std.testing.allocator;
    const sources = [_][]const RetrievalCandidate{

test "two sources merge by key, higher combined rank wins" {
    const allocator = std.testing.allocator;
    // Source 1: a (rank 1), b (rank 2)
    // Source 2: b (rank 1), c (rank 2)
    const sources = [_][]const RetrievalCandidate{

test "duplicate keys across sources accumulate score" {
    const allocator = std.testing.allocator;
    const s1 = [_]RetrievalCandidate{

test "empty source list returns empty" {
    const allocator = std.testing.allocator;
    const sources = [_][]const RetrievalCandidate{

test "all sources empty returns empty" {
    const allocator = std.testing.allocator;
    const empty1 = [_]RetrievalCandidate{

test "limit truncates correctly" {
    const allocator = std.testing.allocator;
    const sources = [_][]const RetrievalCandidate{

test "k=0 vs k=60 changes relative scores" {
    const allocator = std.testing.allocator;
    const sources = [_][]const RetrievalCandidate{

test "candidates from single source only get single RRF term" {
    const allocator = std.testing.allocator;
    const s1 = [_]RetrievalCandidate{

test "large k smooths rank differences" {
    const allocator = std.testing.allocator;
    const sources = [_][]const RetrievalCandidate{

test "single source with limit 0 returns empty" {
    const allocator = std.testing.allocator;
    const src = [_]RetrievalCandidate{

test "three sources merge correctly" {
    const allocator = std.testing.allocator;
    // "a" appears in all 3 sources, "b" in 2, "c" in 1
    const s1 = [_]RetrievalCandidate{

test "preserves first-seen candidate content" {
    const allocator = std.testing.allocator;
    const s1 = [_]RetrievalCandidate{

// ── Test helpers ───────────────────────────────────────────────────

fn makeTestCandidate(key: []const u8, content: []const u8) RetrievalCandidate

fn makeTestCandidateWithSource(key: []const u8, content: []const u8, source: []const u8) RetrievalCandidate
