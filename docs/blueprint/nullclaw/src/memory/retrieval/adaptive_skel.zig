//! Adaptive retrieval strategy selection.
//!
//! Analyzes query characteristics (token count, special chars, question words)
//! and recommends the optimal retrieval strategy: keyword-only, vector-only,
//! or hybrid. This avoids always running both search paths when a simpler
//! strategy would suffice.

const std = @import("std");

pub const RetrievalStrategy = enum {

pub const AdaptiveConfig = struct {
    // Between keyword_max_tokens and vector_min_tokens → hybrid

pub const QueryAnalysis = struct {

/// Analyze a query and recommend a retrieval strategy.
/// Pure function — no allocations, no side effects.
pub fn analyzeQuery(query: []const u8, config: AdaptiveConfig) QueryAnalysis

/// Check if query starts with a question word.
fn isQuestionQuery(query: []const u8) bool

// ── Tests ──────────────────────────────────────────────────────────

const testing = std.testing;

const enabled_config = AdaptiveConfig{