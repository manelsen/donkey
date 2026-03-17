//! QMD retrieval adapter — spawns `qmd` CLI for search, parses JSON results.
//!
//! Follows the pattern in lucid.zig (runLucidCommand) and uses
//! process_util.run() for child process spawning.

const std = @import("std");
const Allocator = std.mem.Allocator;
const retrieval = @import("engine.zig");
const RetrievalCandidate = retrieval.RetrievalCandidate;
const RetrievalSourceAdapter = retrieval.RetrievalSourceAdapter;
const SourceCapabilities = retrieval.SourceCapabilities;
const config_types = @import("../../config_types.zig");
const fs_compat = @import("../../fs_compat.zig");
const process_util = @import("../../tools/process_util.zig");
const root = @import("../root.zig");
const log = std.log.scoped(.qmd);

pub const QmdAdapter = struct {

// ── Tests ──────────────────────────────────────────────────────────

test "QmdAdapter.init stores config" {
    const allocator = std.testing.allocator;
    const cfg = config_types.MemoryQmdConfig{

test "name() returns qmd" {
    const allocator = std.testing.allocator;
    var qa = QmdAdapter.init(allocator, .{

test "capabilities() correct" {
    const allocator = std.testing.allocator;
    var qa = QmdAdapter.init(allocator, .{

test "parseQmdJson parses valid JSON array" {
    const allocator = std.testing.allocator;
    const results = try QmdAdapter.parseQmdJson(allocator, json, .{

test "parseQmdJson handles empty array" {
    const allocator = std.testing.allocator;
    const results = try QmdAdapter.parseQmdJson(allocator, "[]", .{

test "parseQmdJson handles malformed JSON" {
    const allocator = std.testing.allocator;
    const results = try QmdAdapter.parseQmdJson(allocator, "not json at all", .{

test "parseQmdJson handles empty input" {
    const allocator = std.testing.allocator;
    const results = try QmdAdapter.parseQmdJson(allocator, "", .{

test "max_snippet_chars truncation" {
    const allocator = std.testing.allocator;
    const long_content = "A" ** 1000;


    // content should be full

test "max_injected_chars total limit" {
    const allocator = std.testing.allocator;
    const content_200 = "B" ** 200;


    // Should have at most 2 results (200 + 150 = 350)

test "keywordCandidates with non-existent binary returns empty" {
    const allocator = std.testing.allocator;
    const a = qa.adapter();
    const results = try a.keywordCandidates(allocator, "query", 5, null);

test "healthCheck with non-existent binary returns false" {
    const allocator = std.testing.allocator;
    const a = qa.adapter();

test "keyword_rank is 1-based" {
    const allocator = std.testing.allocator;
    const results = try QmdAdapter.parseQmdJson(allocator, json, .{

test "parseQmdJson uses title when path is empty" {
    const allocator = std.testing.allocator;
    const results = try QmdAdapter.parseQmdJson(allocator, json, .{

test "parseQmdJson skips entries with no key and no content" {
    const allocator = std.testing.allocator;
    const results = try QmdAdapter.parseQmdJson(allocator, json, .{

// ── Session export tests ───────────────────────────────────────────

const MockSessionStore = struct {

test "exportSessions with mock session store writes files" {
    const allocator = std.testing.allocator;

    // Create temp dir
    var tmp = std.testing.tmpDir(.{

test "exportSessions skips unchanged files (hash check)" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "exportSessions with empty session list returns 0" {
    const allocator = std.testing.allocator;
    var mock = MockSessionStore{

test "exportSessions with disabled config returns 0" {
    const allocator = std.testing.allocator;
    var mock = MockSessionStore{

test "exportSessions skips unsafe session ids" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "pruneExportedSessions deletes old files" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{
