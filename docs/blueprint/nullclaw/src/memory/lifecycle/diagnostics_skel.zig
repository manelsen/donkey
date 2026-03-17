//! Memory doctor — diagnostics for the memory subsystem.
//!
//! Produces a DiagnosticReport by querying each component of the
//! MemoryRuntime: primary store, vector plane, outbox, cache,
//! retrieval engine, rollout policy, and lifecycle settings.

const std = @import("std");
const build_options = @import("build_options");
const root = @import("../root.zig");
const registry = @import("../engines/registry.zig");
const cache_mod = @import("cache.zig");
const rollout_mod = @import("rollout.zig");
const outbox_mod = @import("../vector/outbox.zig");
const vector_store_mod = @import("../vector/store.zig");
const retrieval_mod = @import("../retrieval/engine.zig");
const log = std.log.scoped(.memory_doctor);

// ── CacheStats ─────────────────────────────────────────────────────

pub const CacheStats = struct {

// ── DiagnosticReport ───────────────────────────────────────────────

pub const DiagnosticReport = struct {
    // Extended pipeline stages

// ── diagnose ───────────────────────────────────────────────────────

/// Populate a DiagnosticReport by inspecting all components of a MemoryRuntime.
pub fn diagnose(rt: *root.MemoryRuntime) DiagnosticReport

// ── formatReport ───────────────────────────────────────────────────

/// Render a DiagnosticReport as human-readable text.
/// Caller owns the returned slice.
pub fn formatReport(report: DiagnosticReport, allocator: std.mem.Allocator) ![]u8

// ── Tests ──────────────────────────────────────────────────────────

const testing = std.testing;


fn makeTestRuntime(allocator: std.mem.Allocator) !struct

test "diagnose with none backend" {
    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    const report = diagnose(&setup.rt);


test "diagnose with sqlite backend and entries" {

    const allocator = testing.allocator;
    const impl_ = try allocator.create(root.SqliteMemory);

    const mem = impl_.memory();

    // Store some entries


    const report = diagnose(&rt);


test "diagnose with response cache" {

    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    // Create a response cache
    const rc = try allocator.create(cache_mod.ResponseCache);

    // Add a cache entry
    var key_buf: [16]u8 = undefined;
    const key_hex = cache_mod.ResponseCache.cacheKeyHex(&key_buf, "gpt-4", null, "test");

    // Hit it once
    const r = try rc.get(allocator, key_hex);

    const report = diagnose(&setup.rt);

    const cs = report.cache_stats.?;

test "diagnose with vector store" {

    const allocator = testing.allocator;
    const sqlite_impl = try allocator.create(root.SqliteMemory);

    const vs = try allocator.create(vector_store_mod.SqliteSharedVectorStore);

    // Upsert a vector
    const vs_iface = vs.store();


    const report = diagnose(&rt);


test "diagnose with outbox" {

    const allocator = testing.allocator;
    const sqlite_impl = try allocator.create(root.SqliteMemory);

    const ob = try allocator.create(outbox_mod.VectorOutbox);

    // Enqueue an item


    const report = diagnose(&rt);


test "diagnose with retrieval engine" {
    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    // Create a retrieval engine with a primary adapter
    const config_types = @import("../../config_types.zig");
    const eng = try allocator.create(retrieval_mod.RetrievalEngine);

    const primary = try allocator.create(retrieval_mod.PrimaryAdapter);


    const report = diagnose(&setup.rt);


test "diagnose rollout mode" {
    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    // Default rollout mode is 'on'
    const report = diagnose(&setup.rt);

test "diagnose rollout mode shadow" {
    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    const report = diagnose(&setup.rt);

test "diagnose rollout mode canary" {
    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    const report = diagnose(&setup.rt);

test "diagnose rollout mode off" {
    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    const report = diagnose(&setup.rt);

test "formatReport produces valid output" {
    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    const report = diagnose(&setup.rt);
    const text = try formatReport(report, allocator);

    // Check key sections present

test "formatReport with cache stats" {
    const allocator = testing.allocator;

    const text = try formatReport(report, allocator);


test "formatReport without optional components" {
    const allocator = testing.allocator;

    const text = try formatReport(report, allocator);


// ── R3 Tests ──────────────────────────────────────────────────────

test "R3: diagnose on empty system returns valid report with formatReport" {
    const allocator = testing.allocator;
    var setup = try makeTestRuntime(allocator);

    const report = diagnose(&setup.rt);

    // Verify defaults

    // Format it — should not crash and should produce non-empty output
    const text = try formatReport(report, allocator);

    // Check Pipeline Stages section is present (extended fields)
