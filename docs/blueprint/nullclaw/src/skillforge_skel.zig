const std = @import("std");
const json_miniparse = @import("json_miniparse.zig");

// SkillForge -- skill auto-discovery, evaluation, and integration engine.
//
// Mirrors ZeroClaw's skillforge module: Scout -> Evaluate -> Integrate pipeline.
// Discovers skills from external sources, scores them, and generates
// compatible manifests for qualified candidates.

// ── Configuration ───────────────────────────────────────────────

pub const SkillForgeConfig = struct {

// ── Scout Types ─────────────────────────────────────────────────

pub const ScoutSource = enum {

pub const ScoutResult = struct {

/// A skill candidate with parsed metadata from scout results.
pub const SkillCandidate = struct {

// ── Scout ────────────────────────────────────────────────────────

/// Scout: search GitHub for nullclaw-compatible skill repositories.
/// Uses api.github.com/search/repositories?q=QUERY+topic:nullclaw
pub fn scout(allocator: std.mem.Allocator, query: []const u8) !std.ArrayList(SkillCandidate)

/// Parse GitHub API /search/repositories JSON response into SkillCandidate entries.
/// Uses minimal manual parsing to avoid pulling in std.json for the full response.
fn parseGitHubSearchResults(allocator: std.mem.Allocator, body: []const u8, candidates: *std.ArrayList(SkillCandidate)) !void