// src/bootstrap/integration_test.zig
//! Integration tests for the bootstrap provider factory and full lifecycle.

const std = @import("std");
const bootstrap_root = @import("root.zig");
const memory_root = @import("../memory/root.zig");
const InMemoryLruMemory = memory_root.InMemoryLruMemory;

const testing = std.testing;

test "factory creates working FileBootstrapProvider for hybrid backend" {
    var tmp = testing.tmpDir(.{

test "factory creates working MemoryBootstrapProvider for sqlite backend" {
    var lru = InMemoryLruMemory.init(testing.allocator, 100);

    const bp = try bootstrap_root.createProvider(testing.allocator, "sqlite", lru.memory(), null);

    const loaded = try bp.load(testing.allocator, "AGENTS.md");

    // Verify it lives in memory, not on disk.

test "MemoryBootstrapProvider disk fallback works via factory" {
    var tmp = testing.tmpDir(.{

test "factory creates NullBootstrapProvider for none backend" {
    const bp = try bootstrap_root.createProvider(testing.allocator, "none", null, null);

    const loaded = try bp.load(testing.allocator, "SOUL.md");

test "factory creates NullBootstrapProvider for memory backend" {
    const bp = try bootstrap_root.createProvider(testing.allocator, "memory", null, null);

    const loaded = try bp.load(testing.allocator, "AGENTS.md");
