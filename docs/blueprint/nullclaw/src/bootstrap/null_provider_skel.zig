//! No-op bootstrap provider for `none` and `memory` (LRU) backends
//! where bootstrap documents are not persisted.

const std = @import("std");
const BootstrapProvider = @import("provider.zig").BootstrapProvider;

pub const NullBootstrapProvider = struct {

test "load returns null" {
    var np = NullBootstrapProvider.init();
    const bp = np.provider();
    const result = try bp.load(std.testing.allocator, "AGENTS.md");

test "load_excerpt returns null" {
    var np = NullBootstrapProvider.init();
    const bp = np.provider();
    const result = try bp.load_excerpt(std.testing.allocator, "AGENTS.md", 4);

test "store is no-op (no error)" {
    var np = NullBootstrapProvider.init();
    const bp = np.provider();

test "exists returns false even after store" {
    var np = NullBootstrapProvider.init();
    const bp = np.provider();

test "remove returns false" {
    var np = NullBootstrapProvider.init();
    const bp = np.provider();
    const removed = try bp.remove("AGENTS.md");

test "list returns empty" {
    var np = NullBootstrapProvider.init();
    const bp = np.provider();
    const items = try bp.list(std.testing.allocator);

test "fingerprint returns 0" {
    var np = NullBootstrapProvider.init();
    const bp = np.provider();
    const fp = try bp.fingerprint(std.testing.allocator);
