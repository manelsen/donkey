const std = @import("std");

/// Standalone action tracker for rate limiting.
/// This is a convenience wrapper that can be used independently of SecurityPolicy.
///
/// Tracks actions in a sliding window (default 1 hour) and provides
/// rate limiting functionality.
pub const RateTracker = struct {
    /// Timestamps of recent actions in nanoseconds (monotonic)
    /// Window duration in nanoseconds
    /// Maximum allowed actions per window
    /// Default window: 1 hour

// ── Tests ──────────────────────────────────────────────────────────────

test "rate tracker starts empty" {
    var tracker = RateTracker.init(std.testing.allocator, 10);

test "rate tracker records and counts" {
    var tracker = RateTracker.init(std.testing.allocator, 10);

test "rate tracker blocks when over limit" {
    var tracker = RateTracker.init(std.testing.allocator, 3);

test "rate tracker is limited at boundary" {
    var tracker = RateTracker.init(std.testing.allocator, 2);

test "rate tracker zero limit blocks everything" {
    var tracker = RateTracker.init(std.testing.allocator, 0);

test "rate tracker reset clears actions" {
    var tracker = RateTracker.init(std.testing.allocator, 5);


test "rate tracker high limit allows many" {
    var tracker = RateTracker.init(std.testing.allocator, 10000);

test "rate tracker remaining decreases" {
    var tracker = RateTracker.init(std.testing.allocator, 5);

test "rate tracker remaining at zero when full" {
    var tracker = RateTracker.init(std.testing.allocator, 2);

test "rate tracker remaining stays at zero when over limit" {
    var tracker = RateTracker.init(std.testing.allocator, 1);

test "rate tracker reset then reuse" {
    var tracker = RateTracker.init(std.testing.allocator, 3);


test "rate tracker custom window" {
    // Use a very large window (effectively infinite)
    var tracker = RateTracker.initWithWindow(std.testing.allocator, 5, 3600 * std.time.ns_per_s * 24);

test "rate tracker init with window preserves params" {
    var tracker = RateTracker.initWithWindow(std.testing.allocator, 42, 999);

test "rate tracker limit of one" {
    var tracker = RateTracker.init(std.testing.allocator, 1);

test "rate tracker many actions count correct" {
    var tracker = RateTracker.init(std.testing.allocator, 1000);
