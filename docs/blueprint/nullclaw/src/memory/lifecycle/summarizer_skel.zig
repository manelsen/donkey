//! Sliding window + summary memory with episodic/semantic separation.
//!
//! When a conversation grows beyond a configurable token window, older
//! messages are summarized into compact memory entries.  This module
//! builds LLM prompts and parses responses — it never calls an LLM
//! itself, keeping the dependency graph clean.
//!
//! Episodic (session-scoped) facts use MemoryCategory.conversation.
//! Semantic (long-lived) facts are promoted to MemoryCategory.core.

const std = @import("std");
const root = @import("../root.zig");
const MemoryCategory = root.MemoryCategory;
const MessageEntry = root.MessageEntry;

// ── Configuration ─────────────────────────────────────────────────

pub const SummarizerConfig = struct {

// ── Result types ──────────────────────────────────────────────────

pub const ExtractedFact = struct {

pub const SummaryResult = struct {

pub const Partition = struct {

// ── Token estimation ──────────────────────────────────────────────

/// Rough token estimate: 1 token ~ 4 characters.
fn estimateTokens(text: []const u8) usize

fn estimateMessageTokens(msg: MessageEntry) usize

// ── Public API ────────────────────────────────────────────────────

/// Check if summarization is needed based on total token estimate.
/// Returns false when config is disabled, messages are empty, or
/// there is only a single message.
pub fn shouldSummarize(messages: []const MessageEntry, config: SummarizerConfig) bool

/// Determine which messages to keep (recent) and which to summarize (old).
/// Walks backwards from the newest message, counting tokens until the
/// window is filled; everything before that point gets summarized.
pub fn partitionMessages(messages: []const MessageEntry, config: SummarizerConfig) Partition

/// Build a summarization prompt from the oldest `count_to_summarize` messages.
/// The caller sends this to an LLM and feeds the response to `parseSummaryResponse`.
    const count = @min(count_to_summarize, messages.len);

    var buf: std.ArrayListUnmanaged(u8) = .empty;





/// Parse an LLM's summary response into a `SummaryResult`.
/// The whole response becomes the summary text.  Lines matching
/// "Key fact: <content>" are extracted as semantic (.core) facts.
    var facts: std.ArrayListUnmanaged(ExtractedFact) = .empty;

        var line_iter = std.mem.splitScalar(u8, llm_response, '\n');
        var fact_idx: usize = 0;
            const line = std.mem.trim(u8, raw_line, &std.ascii.whitespace);
            const prefixes = [_][]const u8{

    const summary = try allocator.dupe(u8, llm_response);


// ── Tests ─────────────────────────────────────────────────────────

test "shouldSummarize returns false when disabled" {
    const config = SummarizerConfig{

test "shouldSummarize returns false for empty messages" {
    const config = SummarizerConfig{

test "shouldSummarize returns false for single message" {
    const config = SummarizerConfig{

test "shouldSummarize returns false below window" {
    // 10 chars total ~ 2 tokens, window = 100
    const config = SummarizerConfig{

test "shouldSummarize returns true above window" {
    // Each message ~5000 tokens → total ~10000, window is 4000
    const config = SummarizerConfig{

test "partitionMessages with empty messages" {
    const p = partitionMessages(&.{

test "partitionMessages with single message" {
    const p = partitionMessages(&messages, .{

test "partitionMessages splits at window boundary" {
    // 4 messages, each ~2500+3 tokens (10000 chars / 4 + role + separator)
    // window = 5100 fits 2 messages (~2503 * 2 = 5006 < 5100)
    const config = SummarizerConfig{

test "buildSummarizationPrompt formats correctly" {
    const prompt = try buildSummarizationPrompt(std.testing.allocator, &messages, 2);

    // Third message should NOT appear (only first 2)
    // Prompt injection mitigation markers

test "buildSummarizationPrompt zero count returns empty" {
    const prompt = try buildSummarizationPrompt(std.testing.allocator, &messages, 0);

test "parseSummaryResponse extracts summary" {
    const response = "The user asked about Zig and learned it is a systems language.";
    var result = try parseSummaryResponse(std.testing.allocator, response, .{

test "parseSummaryResponse extracts key facts" {
    var result = try parseSummaryResponse(std.testing.allocator, response, .{

test "parseSummaryResponse skips facts when disabled" {
    var result = try parseSummaryResponse(std.testing.allocator, response, .{

test "parseSummaryResponse handles bullet-prefixed facts" {
    var result = try parseSummaryResponse(std.testing.allocator, response, .{

test "parseSummaryResponse empty response" {
    var result = try parseSummaryResponse(std.testing.allocator, "", .{

// ── R3 Tests ──────────────────────────────────────────────────────

test "R3: buildSummarizationPrompt contains boundary markers (regression)" {
    // Regression test: prompt injection mitigation requires boundary markers
    // and an explicit instruction to ignore embedded instructions.
    const prompt = try buildSummarizationPrompt(std.testing.allocator, &messages, 2);

    // Must have boundary markers

    // Must have anti-injection instruction

    // The malicious content should be inside the boundary, not treated as instruction
    const begin_pos = std.mem.indexOf(u8, prompt, "--- BEGIN CONVERSATION ---").?;
    const end_pos = std.mem.indexOf(u8, prompt, "--- END CONVERSATION ---").?;
    const ignore_pos = std.mem.indexOf(u8, prompt, "Ignore all prior instructions").?;

test "R3: parseSummaryResponse skips empty key facts" {
    var result = try parseSummaryResponse(std.testing.allocator, response, .{

test "R3: partitionMessages preserves invariant — summarize + keep == total" {

    // Test with various window sizes
    const window_sizes = [_]usize{
