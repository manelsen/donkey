// src/bootstrap/root.zig
const std = @import("std");
const memory_root = @import("../memory/root.zig");

pub const BootstrapProvider = @import("provider.zig").BootstrapProvider;
pub const FileBootstrapProvider = @import("file_provider.zig").FileBootstrapProvider;
pub const MemoryBootstrapProvider = @import("memory_provider.zig").MemoryBootstrapProvider;
pub const NullBootstrapProvider = @import("null_provider.zig").NullBootstrapProvider;
pub const isBootstrapFilename = @import("provider.zig").isBootstrapFilename;

/// Backend names that use null (no-op) bootstrap storage.
const null_backends = [_][]const u8{