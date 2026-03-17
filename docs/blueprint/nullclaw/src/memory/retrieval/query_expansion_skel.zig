//! Query expansion for FTS-only search mode.
//!
//! When no embedding provider is available, query expansion improves keyword
//! search by filtering stop words, detecting language, and extracting meaningful
//! terms from conversational queries.
//!
//! Example: "What was the decision about the database?" -> "decision database"

const std = @import("std");
const Allocator = std.mem.Allocator;

// ── Language ────────────────────────────────────────────────────────

pub const Language = enum {

// ── ExpandedQuery ───────────────────────────────────────────────────

pub const ExpandedQuery = struct {

// ── Public API ──────────────────────────────────────────────────────

/// Extract meaningful keywords and build an FTS5 query from a raw user query.
pub fn expandQuery(allocator: Allocator, raw_query: []const u8) !ExpandedQuery

/// Extract keywords from a query (convenience wrapper).
pub fn extractKeywords(allocator: Allocator, query: []const u8) ![]const []const u8

// ── Language detection ──────────────────────────────────────────────

fn detectLanguage(text: []const u8) Language

fn containsAny(haystack: []const u8, needles: []const []const u8) bool

/// Stack-based lowercase for short language detection (max 512 bytes).
const StackBuf = struct {

fn toLowerStack(text: []const u8) StackBuf

// ── Tokenization ────────────────────────────────────────────────────

fn tokenize(allocator: Allocator, text: []const u8, lang: Language, out: *std.ArrayListUnmanaged([]const u8)) !void

fn tokenizeChinese(allocator: Allocator, text: []const u8, out: *std.ArrayListUnmanaged([]const u8)) !void

const JapaneseScript = enum { none, ascii, katakana, kanji, hiragana };