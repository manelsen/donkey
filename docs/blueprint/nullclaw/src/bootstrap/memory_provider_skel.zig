//! Memory-backed BootstrapProvider.
//!
//! Delegates to the Memory vtable using `__bootstrap.prompt.<filename>` keys.
//! Supports an optional workspace_dir for graceful disk fallback during
//! migration from file-based to memory-based bootstrap storage.

const std = @import("std");
const provider = @import("provider.zig");
const BootstrapProvider = provider.BootstrapProvider;
const isBootstrapFilename = provider.isBootstrapFilename;
const memory_root = @import("../memory/root.zig");
const Memory = memory_root.Memory;

pub const Error = error{