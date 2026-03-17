//! History compaction — token estimation, auto-compaction, force-compression, trimming.
//!
//! Extracted from agent/root.zig. All functions operate on history slices
//! passed by the caller; no dependency on the Agent struct.

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.agent);
const providers = @import("../providers/root.zig");
const config_types = @import("../config_types.zig");
const path_prefix = @import("../path_prefix.zig");
const Provider = providers.Provider;
const ChatMessage = providers.ChatMessage;
const bootstrap_mod = @import("../bootstrap/root.zig");
const BootstrapProvider = bootstrap_mod.BootstrapProvider;
const pathStartsWith = path_prefix.pathStartsWith;

const Agent = @import("root.zig").Agent;
const OwnedMessage = Agent.OwnedMessage;

// ═══════════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════════

/// Default: keep this many most-recent non-system messages after compaction.
pub const DEFAULT_COMPACTION_KEEP_RECENT: u32 = 20;

/// Default: max characters retained in stored compaction summary.
pub const DEFAULT_COMPACTION_MAX_SUMMARY_CHARS: u32 = 2_000;
/// Maximum characters appended from workspace critical rules.
const MAX_WORKSPACE_CONTEXT_CHARS: usize = 2_000;
/// Maximum AGENTS.md bytes read for critical rules extraction.
const MAX_AGENTS_FILE_BYTES: usize = 2 * 1024 * 1024;

/// Default: max characters in source transcript passed to the summarizer.
pub const DEFAULT_COMPACTION_MAX_SOURCE_CHARS: u32 = 12_000;

/// Default token limit for context window (used by token-based compaction trigger).
pub const DEFAULT_TOKEN_LIMIT: u64 = config_types.DEFAULT_AGENT_TOKEN_LIMIT;

/// Minimum history length before context exhaustion recovery is attempted.
pub const CONTEXT_RECOVERY_MIN_HISTORY: usize = 6;

/// Number of recent messages to keep during force compression.
pub const CONTEXT_RECOVERY_KEEP: usize = 4;

// ═══════════════════════════════════════════════════════════════════════════
// Config
// ═══════════════════════════════════════════════════════════════════════════

pub const CompactionConfig = struct {

// ═══════════════════════════════════════════════════════════════════════════
// Public functions
// ═══════════════════════════════════════════════════════════════════════════

/// Estimate total tokens in conversation history using heuristic: (total_chars + 3) / 4.
pub fn tokenEstimate(history: []const OwnedMessage) u64

/// Auto-compact history when it exceeds max_history_messages or when
/// estimated token usage exceeds 75% of the configured token limit.
/// For large histories (>10 messages to summarize), uses multi-part strategy:
/// splits into halves, summarizes each independently, then merges.
/// Returns true if compaction was performed.
    const has_system = history.items.len > 0 and history.items[0].role == .system;
    const start: usize = if (has_system) 1 else 0;
    const non_system_count = history.items.len - start;

    // Trigger on message count exceeding threshold
    const count_trigger = non_system_count > config.max_history_messages;

    // Trigger on token estimate exceeding 75% of token limit
    const token_threshold = (config.token_limit * 3) / 4;
    const token_trigger = config.token_limit > 0 and tokenEstimate(history.items) > token_threshold;


    const keep_recent = @min(config.keep_recent, @as(u32, @intCast(non_system_count)));
    const compact_count = non_system_count - keep_recent;

    const compact_end = start + compact_count;

    // Multi-part strategy: if >10 messages to summarize, split into halves
        const mid = start + compact_count / 2;

        // Summarize first half
        const summary_a = try summarizeSlice(allocator, provider, model_name, history.items, start, mid, config);

        // Summarize second half
        const summary_b = try summarizeSlice(allocator, provider, model_name, history.items, mid, compact_end, config);

        // Merge the two summaries

        // Truncate if too long
            const truncated = try allocator.dupe(u8, merged[0..config.max_summary_chars]);


    const workspace_context = try readWorkspaceContextForSummary(allocator, config.workspace_dir, config.bootstrap_provider);


    // Create the compaction summary message
    const summary_content = try std.fmt.allocPrint(allocator, "[Compaction summary]\n{

/// Force-compress history for context exhaustion recovery.
/// Keeps system prompt (if any) + last CONTEXT_RECOVERY_KEEP messages.
/// Everything in between is dropped without LLM summarization (we can't call
/// the LLM since the context is exhausted). Returns true if compression was performed.
    const has_system = history.items.len > 0 and history.items[0].role == .system;
    const start: usize = if (has_system) 1 else 0;
    const non_system_count = history.items.len - start;


    const keep_start = history.items.len - CONTEXT_RECOVERY_KEEP;
    const to_remove = keep_start - start;

    // Free messages being removed

    // Shift remaining elements
    const src = history.items[keep_start..];


/// Trim history to prevent unbounded growth.
/// Preserves the system prompt (first message) and the most recent messages.
    const max = max_history_messages;

    const has_system = history.items.len > 0 and history.items[0].role == .system;
    const start: usize = if (has_system) 1 else 0;
    const non_system_count = history.items.len - start;


    const to_remove = non_system_count - max;
    // Free the messages being removed

    // Shift remaining elements
    const src = history.items[start + to_remove ..];

    // Shrink backing array if capacity is much larger than needed

// ═══════════════════════════════════════════════════════════════════════════
// Internal helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Build a compaction transcript from a slice of history messages.
    var buf: std.ArrayList(u8) = .empty;

        // Truncate very long messages in transcript
        const content = if (msg.content.len > 500) msg.content[0..500] else msg.content;

        // Safety cap



/// Summarize a slice of history messages via the LLM provider.
/// Returns an owned summary string. Falls back to transcript truncation on error.
    const transcript = try buildCompactionTranscript(allocator, history_items, start, end, config.max_source_chars);

    const summarizer_system = "You are a conversation compaction engine. Summarize older chat history into concise context for future turns. Preserve: user preferences, commitments, decisions, unresolved tasks, key facts. Omit: filler, repeated chit-chat, verbose tool logs. Output plain text bullet points only.";
    const summarizer_user = try std.fmt.allocPrint(allocator, "Summarize the following conversation history for context preservation. Keep it short (max 12 bullet points).\n\n{

const HeadingInfo = struct {

fn parseHeadingLine(line: []const u8) ?HeadingInfo


    var out: std.ArrayListUnmanaged(u8) = .empty;

    var in_section = false;
    var section_level: u8 = 0;
    var in_code_block = false;
    var has_any = false;

    var lines = std.mem.splitScalar(u8, content, '\n');
        const left_trimmed = std.mem.trimLeft(u8, line, " \t");




    const raw = try out.toOwnedSlice(allocator);

    const trimmed = std.mem.trim(u8, raw, " \t\r\n");

    const duped = try allocator.dupe(u8, trimmed);

    var combined: std.ArrayListUnmanaged(u8) = .empty;

        const maybe_section = try extractNamedSection(allocator, content, section_name);


    const workspace_root = std.fs.cwd().realpathAlloc(allocator, workspace_dir) catch return null;

    const agents_candidate = std.fs.path.join(allocator, &.{

    // Try bootstrap provider first when available.
        const bp_content = bp.load_excerpt(allocator, "AGENTS.md", MAX_AGENTS_FILE_BYTES) catch null;
            const sections = try extractSections(allocator, content, &.{

    // Fallback: direct file read.
    const dir = workspace_dir orelse return try allocator.dupe(u8, "");
    const file = openWorkspaceAgentsFileGuarded(allocator, dir) orelse return try allocator.dupe(u8, "");

    const content = file.readToEndAlloc(allocator, MAX_AGENTS_FILE_BYTES) catch return try allocator.dupe(u8, "");

    const sections = try extractSections(allocator, content, &.{

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

const observability = @import("../observability.zig");
const ToolSpec = providers.ToolSpec;

fn makeTestAgent(allocator: std.mem.Allocator) !Agent

test "tokenEstimate empty history" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    // Empty history: (0 + 3) / 4 = 0

test "tokenEstimate with messages" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    // Add messages with known content lengths
    // "hello" = 5 chars, "world" = 5 chars => total 10 chars => (10 + 3) / 4 = 3


test "tokenEstimate heuristic accuracy" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    // 400 chars should estimate ~100 tokens
    const content = try allocator.alloc(u8, 400);


    // (400 + 3) / 4 = 100

test "autoCompactHistory no-op below count and token thresholds" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    // Add a few small messages — well below both thresholds


test "DEFAULT_TOKEN_LIMIT constant" {

test "forceCompressHistory keeps system + last 4 messages" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    // Add system prompt + 8 messages

    const compressed = forceCompressHistory(allocator, &agent.history);

    // Should keep system + last 4

test "forceCompressHistory without system prompt" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    // Add 8 messages (no system prompt)

    const compressed = forceCompressHistory(allocator, &agent.history);

    // Should keep last 4

test "forceCompressHistory no-op when history is small" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);


    const compressed = forceCompressHistory(allocator, &agent.history);

test "CONTEXT_RECOVERY constants" {

test "extractSections captures Session Startup and Red Lines, ignoring code fences" {

    const sections = try extractSections(std.testing.allocator, content, &.{

test "readWorkspaceContextForSummary wraps AGENTS critical sections" {
    var tmp = std.testing.tmpDir(.{

test "readWorkspaceContextForSummary returns empty when AGENTS missing" {
    var tmp = std.testing.tmpDir(.{

test "readWorkspaceContextForSummary blocks AGENTS symlink escape" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    var ws_tmp = std.testing.tmpDir(.{
