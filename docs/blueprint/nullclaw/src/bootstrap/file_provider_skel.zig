// src/bootstrap/file_provider.zig
const std = @import("std");
const provider = @import("provider.zig");
const BootstrapProvider = provider.BootstrapProvider;
const isBootstrapFilename = provider.isBootstrapFilename;
const memory_root = @import("../memory/root.zig");

pub const Error = error{