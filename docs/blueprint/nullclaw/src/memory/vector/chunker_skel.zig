//! Line-based markdown chunker — splits documents into semantic chunks.
//!
//! Splits on markdown headings and paragraph boundaries, respecting
//! a max token limit per chunk. Preserves heading context.

const std = @import("std");

/// A single chunk of text with metadata.
pub const Chunk = struct {

/// Split markdown text into chunks, each under `max_tokens` approximate tokens.
///
/// Strategy:
/// 1. Split on `## ` and `# ` headings (keeps heading with its content)
/// 2. If a section exceeds max_tokens, split on blank lines (paragraphs)
/// 3. If a paragraph still exceeds, split on line boundaries
///
/// Token estimation: ~4 chars per token (rough English average).
/// Caller owns the returned slices and must free them with freeChunks.
pub fn chunkMarkdown(allocator: std.mem.Allocator, text: []const u8, max_tokens: usize) ![]Chunk

pub fn freeChunks(allocator: std.mem.Allocator, chunks_slice: []Chunk) void

// ── Internal helpers ───────────────────────────────────────────────

const Section = struct {

fn splitOnHeadings(allocator: std.mem.Allocator, text: []const u8) ![]Section

fn splitOnBlankLines(allocator: std.mem.Allocator, text: []const u8) ![][]u8

fn splitOnLines(allocator: std.mem.Allocator, text: []const u8, max_chars: usize) ![][]u8

// ── Tests ──────────────────────────────────────────────────────────

test "empty text" {
    const chunks_slice = try chunkMarkdown(std.testing.allocator, "", 512);

test "whitespace only" {
    const chunks_slice = try chunkMarkdown(std.testing.allocator, "   \n\n\n  ", 512);

test "single short paragraph" {
    const chunks_slice = try chunkMarkdown(std.testing.allocator, "Hello world", 512);

test "heading sections" {
    const text = "# Title\nSome intro.\n\n## Section A\nContent A.\n\n## Section B\nContent B.";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "indexes are sequential" {
    const text = "# A\nContent A\n\n# B\nContent B\n\n# C\nContent C";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "single heading no content" {
    const text = "# Just a heading";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "max tokens zero does not crash" {
    const chunks_slice = try chunkMarkdown(std.testing.allocator, "Hello world", 0);

test "respects max tokens" {
    var text_builder: std.ArrayList(u8) = .empty;

        const line = try std.fmt.allocPrint(std.testing.allocator, "This is sentence number{

    const chunks_slice = try chunkMarkdown(std.testing.allocator, text_builder.items, 50);

test "no content loss" {
    const text = "# A\nContent A line 1\nContent A line 2\n\n## B\nContent B\n\n## C\nContent C";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

    var all_content: std.ArrayList(u8) = .empty;

    const words = [_][]const u8{

test "headings only no body" {
    const text = "# Title\n## Section A\n## Section B\n### Subsection";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "deeply nested headings stay with parent" {
    // #### and deeper are NOT treated as heading splits
    const text = "# Top\nIntro\n#### Deep heading\nDeep content";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);
    var all_content: std.ArrayList(u8) = .empty;

test "very long single line no newlines" {
    // One giant line with no newlines
    var text_builder: std.ArrayList(u8) = .empty;
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text_builder.items, 50);

test "max tokens one aggressive splitting" {
    const text = "Line one\nLine two\nLine three";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 1);

test "unicode content preserved" {
    const text = "# \xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e\n\xe3\x81\x93\xe3\x82\x93\xe3\x81\xab\xe3\x81\xa1\xe3\x81\xaf\xe4\xb8\x96\xe7\x95\x8c\n\n## Emojis\nZig is great";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);
    var all_content: std.ArrayList(u8) = .empty;

test "fts5 special chars in content" {
    const text = "Content with \"quotes\" and (parentheses) and * asterisks *";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "multiple blank lines between paragraphs" {
    const text = "Paragraph one.\n\n\n\n\nParagraph two.\n\n\n\nParagraph three.";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "heading at end of text" {
    const text = "Some content\n# Trailing Heading";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "preserves heading in split sections" {
    var text_builder: std.ArrayList(u8) = .empty;
        const line = try std.fmt.allocPrint(std.testing.allocator, "Line{
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text_builder.items, 50);

test "chunk count reasonable for small doc" {
    const text = "Hello world. This is a test document.";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "BOM stripped from start of text" {
    // UTF-8 BOM: EF BB BF
    const text = "\xEF\xBB\xBF# Title\nSome content.";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);
    // Heading should be detected despite BOM in original text

test "BOM only text treated as empty" {
    const text = "\xEF\xBB\xBF";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

// ── R3 regression tests ───────────────────────────────────────────

test "empty string produces empty chunks r3" {
    const chunks_slice = try chunkMarkdown(std.testing.allocator, "", 512);

test "single line shorter than max produces one chunk" {
    const text = "Short line.";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);

test "multi-byte UTF-8 text no mid-character splits" {
    // Build text with multi-byte chars that exceeds chunk size
    var text_builder: std.ArrayList(u8) = .empty;
    // 200 repetitions of a 3-byte char (U+4E16 = 世)
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text_builder.items, 10);
    // Verify all chunks contain valid UTF-8 (no mid-character splits)

test "markdown with headings splits on heading boundaries" {
    const text = "# First\nContent of first.\n## Second\nContent of second.\n## Third\nContent of third.";
    const chunks_slice = try chunkMarkdown(std.testing.allocator, text, 512);
    // Should have at least 3 chunks (one per heading section)
    // First chunk should have heading "# First"
    // Second chunk heading
    // Third chunk heading
