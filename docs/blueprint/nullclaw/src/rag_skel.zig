const std = @import("std");

// RAG -- Retrieval-Augmented Generation for hardware datasheets.
//
// Mirrors ZeroClaw's rag module: datasheet chunk indexing,
// pin alias parsing, keyword-based retrieval.

// ── DatasheetChunk ──────────────────────────────────────────────

/// A chunk of datasheet content with board metadata.
pub const DatasheetChunk = struct {
    /// Board this chunk applies to (e.g. "nucleo-f401re"), or null for generic.
    /// Source file path.
    /// Chunk content.

// ── Pin Aliases ─────────────────────────────────────────────────

/// Pin alias: human-readable name to pin number.
pub const PinAlias = struct {

/// Parse pin aliases from markdown content.
/// Looks for a `## Pin Aliases` section with `alias: pin` lines
/// or markdown table `| alias | pin |` rows.
pub fn parsePinAliases(allocator: std.mem.Allocator, content: []const u8) ![]PinAlias

fn parseTableRow(line: []const u8) ?PinAlias

fn parseKeyValue(line: []const u8) ?PinAlias

// ── Board inference ─────────────────────────────────────────────

/// Infer board tag from a file path. "nucleo-f401re.md" -> "nucleo-f401re".
/// Returns null for "generic" or "_generic" paths.
pub fn inferBoardFromPath(path: []const u8) ?[]const u8

// ── HardwareRag ─────────────────────────────────────────────────

/// Hardware RAG index -- stores datasheet chunks and pin aliases.
pub const HardwareRag = struct {

// ── Tests ───────────────────────────────────────────────────────

test "parsePinAliases key-value format" {
    const aliases = try parsePinAliases(std.testing.allocator, md);


test "parsePinAliases table format" {
    const aliases = try parsePinAliases(std.testing.allocator, md);


test "parsePinAliases empty when no section" {
    const aliases = try parsePinAliases(std.testing.allocator, "No aliases here");

test "parsePinAliases equals separator" {
    const aliases = try parsePinAliases(std.testing.allocator, md);

test "parsePinAliases ignores non-numeric values" {
    const aliases = try parsePinAliases(std.testing.allocator, md);

test "parsePinAliases stops at next heading" {
    const aliases = try parsePinAliases(std.testing.allocator, md);

test "inferBoardFromPath basic" {

test "inferBoardFromPath generic returns null" {

test "inferBoardFromPath generic prefix returns null" {

test "inferBoardFromPath _generic dir returns null" {

test "inferBoardFromPath txt extension" {

test "HardwareRag init and deinit" {
    var rag = HardwareRag.init(std.testing.allocator);

test "HardwareRag pinAliasesForBoard returns null when empty" {
    var rag = HardwareRag.init(std.testing.allocator);

test "HardwareRag retrieve returns empty when no chunks" {
    var rag = HardwareRag.init(std.testing.allocator);
    const results = try rag.retrieve(std.testing.allocator, "led", &.{

test "DatasheetChunk defaults" {
        .content = "test content",
