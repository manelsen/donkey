//! Temporal decay — exponential time decay for retrieval candidates.
//!
//! Reduces the final_score of older memories so that recent information
//! is ranked higher.  Applied after hybrid merge but before MMR reranking.
//!
//! Formula:  score *= exp(-lambda * age_days)
//!   where   lambda = ln(2) / half_life_days
//!
//! At age == half_life_days the multiplier is exactly 0.5.
//! Evergreen entries (category == .core) are never decayed.

const std = @import("std");
const retrieval = @import("engine.zig");
const RetrievalCandidate = retrieval.RetrievalCandidate;
const MemoryCategory = @import("../root.zig").MemoryCategory;
const config_types = @import("../../config_types.zig");

pub const TemporalDecayConfig = config_types.MemoryTemporalDecayConfig;

// ── Pure helpers ──────────────────────────────────────────────────

/// Compute the decay constant lambda from a half-life in days.
/// Returns 0 when half_life_days is 0 (i.e. decay is effectively disabled).
pub fn decayLambda(half_life_days: u32) f64

/// Compute the decay multiplier for a given age.
/// Negative ages are clamped to 0 (no decay for future timestamps).
pub fn decayMultiplier(age_in_days: f64, half_life_days: u32) f64

/// Apply decay to a single score value.
pub fn applyDecay(score: f64, age_in_days: f64, half_life_days: u32) f64

/// Check whether a path refers to an evergreen memory file.
pub fn isEvergreen(path: []const u8) bool

// ── Pipeline stage ───────────────────────────────────────────────

const secs_per_day: f64 = 86400.0;

/// Apply temporal decay to candidate scores in-place.
/// Evergreen candidates (category == .core) are not decayed.
/// Candidates with created_at == 0 (unknown timestamp) are not decayed.

    const lambda = decayLambda(config.half_life_days);

        // Skip evergreen (core) entries

        // Skip entries with no known timestamp

        // Use wrapping subtraction to avoid overflow panic when timestamps
        // are at extreme i64 values, then clamp negative ages to 0.
        const age_secs_raw = now_timestamp -% c.created_at;
        const age_secs: f64 = if (age_secs_raw < 0) 0.0 else @floatFromInt(age_secs_raw);
        const age_days = age_secs / secs_per_day;
        const decay = @exp(-lambda * age_days);

// ── Tests ────────────────────────────────────────────────────────

test "decay_lambda_30_days" {
    const lambda = decayLambda(30);

test "decay_lambda_zero_half_life" {
    const lambda = decayLambda(0);

test "decay_multiplier_at_half_life" {
    const m = decayMultiplier(30.0, 30);

test "decay_multiplier_at_zero_age" {
    const m = decayMultiplier(0.0, 30);

test "decay_multiplier_at_double_half_life" {
    const m = decayMultiplier(60.0, 30);

test "apply_decay_to_score" {
    const decayed = applyDecay(0.8, 30.0, 30);

test "negative_age_clamped_to_zero" {
    const m = decayMultiplier(-10.0, 30);

test "zero_half_life_returns_one" {
    const m = decayMultiplier(100.0, 0);

test "is_evergreen_memory_md" {

test "is_evergreen_daily_file" {

fn makeCandidate(category: MemoryCategory, score: f64, created_at: i64) RetrievalCandidate

test "applyTemporalDecay fresh entry unchanged" {
    // now == created_at → 0 days old

test "applyTemporalDecay at half_life halves score" {
    const half_life: u32 = 30;
    const created = 1000000;
    const now = created + 30 * 86400; // exactly 30 days later

test "applyTemporalDecay very old entry near zero" {
    const created = 1000000;
    const now = created + 365 * 86400; // 365 days later

test "applyTemporalDecay core category never decayed" {
    const created = 1000000;
    const now = created + 365 * 86400;

test "applyTemporalDecay disabled config no changes" {
    const created = 1000000;
    const now = created + 365 * 86400;

test "applyTemporalDecay empty candidates no-op" {
    var candidates = [_]RetrievalCandidate{

test "applyTemporalDecay negative age no decay" {
    // created_at is in the future relative to now

test "applyTemporalDecay half_life zero gracefully handled" {
    const created = 1000000;
    const now = created + 30 * 86400;
    // half_life=0 means no decay

test "applyTemporalDecay multiple candidates each decayed independently" {
    const now: i64 = 1000000 + 30 * 86400;

    // 15 days: multiplier = e^(-ln2/30 * 15) = 2^(-0.5) ≈ 0.7071

test "applyTemporalDecay skips entries with unknown timestamp" {

test "applyTemporalDecay conversation category is decayed" {
    const created = 1000000;
    const now = created + 30 * 86400;
