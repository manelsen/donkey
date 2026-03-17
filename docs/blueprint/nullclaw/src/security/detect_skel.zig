const std = @import("std");
const builtin = @import("builtin");
const Sandbox = @import("sandbox.zig").Sandbox;
const NoopSandbox = @import("sandbox.zig").NoopSandbox;
const LandlockSandbox = @import("landlock.zig").LandlockSandbox;
const FirejailSandbox = @import("firejail.zig").FirejailSandbox;
const BubblewrapSandbox = @import("bubblewrap.zig").BubblewrapSandbox;
const DockerSandbox = @import("docker.zig").DockerSandbox;

/// Sandbox backend preference.
pub const SandboxBackend = enum {

/// Detect and create the best available sandbox backend.
///
/// Priority on Linux: landlock > firejail > bubblewrap > docker > noop
/// Priority on macOS: docker > noop
/// Explicit backend selection overrides auto-detection.
    /// Caller-provided storage for sandbox backend structs.
    /// Must remain valid for the lifetime of the returned Sandbox.

/// Storage for sandbox backend instances (union-like, only one is active).
pub const SandboxStorage = struct {

/// Auto-detect the best available sandbox backend.
fn detectBest(allocator: std.mem.Allocator, workspace_dir: []const u8, storage: *SandboxStorage) Sandbox

/// Check which sandbox backends are available on the current system.
/// Returns a struct with boolean flags for each backend.
pub const AvailableBackends = struct {

pub fn detectAvailable(allocator: std.mem.Allocator, workspace_dir: []const u8) AvailableBackends

// ── Tests ──────────────────────────────────────────────────────────────

test "detect available returns struct" {
    const avail = detectAvailable(std.testing.allocator, "/tmp/workspace");
    // On macOS, landlock/firejail/bubblewrap should be false
    if (comptime builtin.os.tag != .linux) {
    // Docker availability is runtime-dependent (not available on all CI machines)

test "create sandbox with none returns noop" {
    var storage: SandboxStorage = .{

test "create sandbox with auto returns something" {
    var storage: SandboxStorage = .{

test "create sandbox with docker returns docker" {
    var storage: SandboxStorage = .{

test "sandbox storage default initialization" {
    const storage = SandboxStorage{
