//! LanceDB-style vector memory backend — SQLite + embedding-based store/recall.
//!
//! Combines SQLite for storage
//! with cosine similarity search for vector-augmented recall. Features:
//!
//! - Duplicate detection: skip entries with >95% cosine similarity
//! - Importance scoring (0.0-1.0) per entry
//! - Full-scan cosine similarity on recall (no ANN index)
//! - Min search score filtering
//! - Category and session isolation
//!
//! Uses the existing vector/math.zig for cosine similarity and serialization.

const std = @import("std");
const build_options = @import("build_options");
const root = @import("../root.zig");
const Memory = root.Memory;
const MemoryCategory = root.MemoryCategory;
const MemoryEntry = root.MemoryEntry;
const vector = @import("../vector/math.zig");
const embeddings_mod = @import("../vector/embeddings.zig");
const EmbeddingProvider = embeddings_mod.EmbeddingProvider;
const log = std.log.scoped(.lancedb_memory);

const sqlite_mod = if (build_options.enable_sqlite) @import("sqlite.zig") else @import("sqlite_disabled.zig");
const c = sqlite_mod.c;
const SQLITE_STATIC = sqlite_mod.SQLITE_STATIC;

// ── Config ────────────────────────────────────────────────────────

pub const LanceDbConfig = struct {

// ── LanceDbMemory ────────────────────────────────────────────────

pub const LanceDbMemory = struct {

// ── Tests ──────────────────────────────────────────────────────────

const testing = std.testing;

test "lancedb store and recall" {
    const allocator = testing.allocator;
    var impl_ = try LanceDbMemory.init(allocator, ":memory:", null, .{

test "lancedb get by key" {
    const allocator = testing.allocator;
    var impl_ = try LanceDbMemory.init(allocator, ":memory:", null, .{

test "lancedb forget" {
    const allocator = testing.allocator;
    var impl_ = try LanceDbMemory.init(allocator, ":memory:", null, .{

test "lancedb list by category" {
    const allocator = testing.allocator;
    var impl_ = try LanceDbMemory.init(allocator, ":memory:", null, .{

test "lancedb empty recall" {
    const allocator = testing.allocator;
    var impl_ = try LanceDbMemory.init(allocator, ":memory:", null, .{

test "lancedb health check" {
    const allocator = testing.allocator;
    var impl_ = try LanceDbMemory.init(allocator, ":memory:", null, .{

test "lancedb upsert updates existing" {
    const allocator = testing.allocator;
    var impl_ = try LanceDbMemory.init(allocator, ":memory:", null, .{

test "lancedb forget nonexistent returns false" {
    const allocator = testing.allocator;
    var impl_ = try LanceDbMemory.init(allocator, ":memory:", null, .{
