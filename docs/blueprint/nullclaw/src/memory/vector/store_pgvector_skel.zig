//! PgvectorVectorStore — VectorStore vtable adapter for PostgreSQL with pgvector.
//!
//! Implements the VectorStore interface using pgvector's cosine distance
//! operator (<=>) for similarity search. Feature-gated behind
//! build_options.enable_postgres.
//!
//! SQL schema:
//!   CREATE EXTENSION IF NOT EXISTS vector;
//!   CREATE TABLE IF NOT EXISTS memory_vectors (
//!     key       TEXT PRIMARY KEY,
//!     embedding vector(N),
//!     updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
//!   );
//!   CREATE INDEX ON memory_vectors USING ivfflat (embedding vector_cosine_ops);

const std = @import("std");
const Allocator = std.mem.Allocator;
const build_options = @import("build_options");
const store_mod = @import("store.zig");
const VectorStore = store_mod.VectorStore;
const VectorResult = store_mod.VectorResult;
const HealthStatus = store_mod.HealthStatus;


// ── Config ────────────────────────────────────────────────────────

pub const PgvectorConfig = struct {

/// Validate that a table name is a safe SQL identifier (alphanumeric + underscore, 1-63 chars).
/// Prevents SQL injection via user-controlled table names.
fn validateTableName(name: []const u8) !void

// ── PgvectorVectorStore ───────────────────────────────────────────

pub const PgvectorVectorStore = struct {

// ── Tests ─────────────────────────────────────────────────────────

test "formatVector basic" {
    const embedding = [_]f32{

test "formatVector single element" {
    const embedding = [_]f32{

test "formatVector empty" {
    const empty: []const f32 = &.{

test "formatVector negative values" {
    const embedding = [_]f32{

test "PgvectorVectorStore init and deinit without postgres" {
    // When postgres is disabled, init should still create the struct
    // but won't connect

test "PgvectorVectorStore produces valid VectorStore vtable" {
    const s = self.store();

test "validateTableName rejects SQL injection" {
    // Valid names

    // SQL injection attempts

test "PgvectorVectorStore init rejects bad table name" {

test "PgvectorVectorStore healthCheck disabled returns not-ok" {
    const s = self.store();

    const status = try s.healthCheck(std.testing.allocator);


// ── R3 tests ──────────────────────────────────────────────────────

test "formatVector rejects NaN" {
    const embedding = [_]f32{

test "formatVector rejects positive Inf" {
    const embedding = [_]f32{

test "formatVector rejects negative Inf" {
    const embedding = [_]f32{
