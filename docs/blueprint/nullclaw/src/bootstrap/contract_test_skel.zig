// src/bootstrap/contract_test.zig
//! Contract tests verifying that every BootstrapProvider implementation
//! satisfies the interface invariants.

const std = @import("std");
const BootstrapProvider = @import("provider.zig").BootstrapProvider;
const FileBootstrapProvider = @import("file_provider.zig").FileBootstrapProvider;
const MemoryBootstrapProvider = @import("memory_provider.zig").MemoryBootstrapProvider;
const NullBootstrapProvider = @import("null_provider.zig").NullBootstrapProvider;
const memory_root = @import("../memory/root.zig");
const InMemoryLruMemory = memory_root.InMemoryLruMemory;

const testing = std.testing;

/// Shared contract: exercises the full BootstrapProvider surface.
/// Every persisting implementation must pass all checks.
fn runContractTests(bp: BootstrapProvider) !void

test "contract: FileBootstrapProvider" {
    var tmp = testing.tmpDir(.{

test "contract: MemoryBootstrapProvider" {
    var lru = InMemoryLruMemory.init(testing.allocator, 100);

    var impl = MemoryBootstrapProvider.init(testing.allocator, lru.memory(), null);
    const bp = impl.provider();

test "contract: NullBootstrapProvider has no-op semantics" {
    var impl = NullBootstrapProvider.init();
    const bp = impl.provider();

    // Null provider: store is no-op, load always null.
    const loaded = try bp.load(testing.allocator, "SOUL.md");
    const excerpt = try bp.load_excerpt(testing.allocator, "SOUL.md", 3);

    // list returns empty.
    const items = try bp.list(testing.allocator);

    // remove returns false.
    const removed = try bp.remove("SOUL.md");

    // fingerprint is always 0.
    const fp = try bp.fingerprint(testing.allocator);
