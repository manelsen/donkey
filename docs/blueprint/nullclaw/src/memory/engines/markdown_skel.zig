//! Markdown-based memory — plain files as source of truth.
//!
//! Layout:
//!   workspace/MEMORY.md          — curated long-term memory (core)
//!   workspace/memory/YYYY-MM-DD.md — daily logs (append-only)
//!
//! This backend is append-only: forget() is a no-op to preserve audit trail.

const std = @import("std");
const fs_compat = @import("../../fs_compat.zig");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;

pub const MarkdownMemory = struct {

// ── Tests ──────────────────────────────────────────────────────────

test "markdown forget always returns false" {
    var mem = try MarkdownMemory.init(std.testing.allocator, "/tmp/nullclaw-test-md-forget");
    const m = mem.memory();

    // Multiple forget calls all return false

test "markdown parseEntries skips empty lines" {
    const text = "line one\n\n\nline two\n";
    const entries = try MarkdownMemory.parseEntries(text, "test", .core, std.testing.allocator);

test "markdown parseEntries skips headings" {
    const text = "# Heading\nContent under heading\n## Sub\nMore content";
    const entries = try MarkdownMemory.parseEntries(text, "test", .core, std.testing.allocator);

test "markdown parseEntries strips bullet prefix" {
    const text = "- Item one\n- Item two\nPlain line";
    const entries = try MarkdownMemory.parseEntries(text, "test", .core, std.testing.allocator);

test "markdown parseEntries generates sequential ids" {
    const text = "a\nb\nc";
    const entries = try MarkdownMemory.parseEntries(text, "myfile", .core, std.testing.allocator);

test "markdown parseEntries empty text returns empty" {
    const entries = try MarkdownMemory.parseEntries("", "test", .core, std.testing.allocator);

test "markdown parseEntries only headings returns empty" {
    const text = "# Heading\n## Another\n### Third";
    const entries = try MarkdownMemory.parseEntries(text, "test", .core, std.testing.allocator);

test "markdown parseEntries preserves category" {
    const text = "content";
    const entries = try MarkdownMemory.parseEntries(text, "test", .daily, std.testing.allocator);

test "markdown accepts session_id param" {
    var tmp = std.testing.tmpDir(.{

test "markdown reads memory.md when MEMORY.md is absent" {
    var tmp = std.testing.tmpDir(.{

test "markdown reads both MEMORY.md and memory.md when distinct" {
    var tmp = std.testing.tmpDir(.{

test "markdown get returns latest matching entry for duplicate key" {
    var tmp = std.testing.tmpDir(.{
