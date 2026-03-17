const std = @import("std");

/// Token usage information from a single API call.
pub const TokenUsage = struct {

/// Time period for cost aggregation.
pub const UsagePeriod = enum {

/// Budget enforcement result.

pub const BudgetInfo = struct {

/// Per-model statistics.
pub const ModelStats = struct {

/// Cost summary for reporting.
pub const CostSummary = struct {

/// A single cost record for persistent storage.
pub const CostRecord = struct {

/// Cost tracker for API usage monitoring and budget enforcement.
/// Uses an in-memory list for session tracking plus JSONL file for persistence.
pub const CostTracker = struct {

/// Parse the "timestamp" field from a JSONL cost record line.
fn parseTimestampFromJsonl(line: []const u8) ?i64

/// Parse the "cost_usd" field from a JSONL cost record line.
fn parseCostFromJsonl(line: []const u8) f64

// ── Tests ────────────────────────────────────────────────────────────

test "TokenUsage cost calculation" {
    const usage = TokenUsage.init("test/model", 1000, 500, 3.0, 15.0);
    // Expected: (1000/1M)*3 + (500/1M)*15 = 0.003 + 0.0075 = 0.0105

test "TokenUsage zero tokens" {
    const usage = TokenUsage.init("test/model", 0, 0, 3.0, 15.0);

test "TokenUsage negative prices clamped to zero" {
    const usage = TokenUsage.init("test/model", 1000, 1000, -3.0, std.math.nan(f64));

test "CostTracker init and record" {
    var tracker = CostTracker.init(std.testing.allocator, "/tmp", true, 10.0, 100.0, 80);

    const usage = TokenUsage.init("test/model", 1000, 500, 1.0, 2.0);


test "CostTracker budget check when disabled" {
    var tracker = CostTracker.init(std.testing.allocator, "/tmp", false, 10.0, 100.0, 80);

    const check = tracker.checkBudget(1000.0);

test "CostTracker budget exceeded" {
    var tracker = CostTracker.init(std.testing.allocator, "/tmp", true, 0.01, 100.0, 80);

    const usage = TokenUsage.init("test/model", 10000, 5000, 1.0, 2.0);

    const check = tracker.checkBudget(0.01);

test "CostTracker summary" {
    var tracker = CostTracker.init(std.testing.allocator, "/tmp", true, 10.0, 100.0, 80);


    const summary = tracker.getSummary();
