const std = @import("std");

/// Sandbox backend vtable interface for OS-level isolation.
/// In Zig, we use a vtable pattern instead of Rust's trait objects.
pub const Sandbox = struct {
        /// Wrap a command with sandbox protection.
        /// Returns a modified argv or error.

/// No-op sandbox (always available, provides no additional isolation)
pub const NoopSandbox = struct {

/// Create a noop sandbox (default fallback)
pub fn createNoopSandbox() NoopSandbox

/// Re-export detect module's createSandbox for convenience.
pub const createSandbox = @import("detect.zig").createSandbox;
pub const SandboxBackend = @import("detect.zig").SandboxBackend;
pub const SandboxStorage = @import("detect.zig").SandboxStorage;
pub const detectAvailable = @import("detect.zig").detectAvailable;
pub const AvailableBackends = @import("detect.zig").AvailableBackends;

// ── Tests ──────────────────────────────────────────────────────────────
