const std = @import("std");
pub const RateTracker = @import("tracker.zig").RateTracker;

/// How much autonomy the agent has
pub const AutonomyLevel = enum {
    /// Read-only: can observe but not act
    /// Supervised: acts but requires approval for risky operations
    /// Full: autonomous execution within policy bounds
    /// YOLO: bypasses all security checks (allowlist, syntax, risk, approval, rate limiting)

/// Risk score for shell command execution.
pub const CommandRiskLevel = enum {

/// High-risk commands that are always blocked/require elevated approval.

/// Default allowed commands

pub const full_autonomy_default_allowed_commands = [_][]const u8{