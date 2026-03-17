// src/bootstrap/provider.zig
const std = @import("std");
const memory_root = @import("../memory/root.zig");

/// Bootstrap document provider — abstracts where identity files are stored.
pub const BootstrapProvider = struct {

/// Check if a filename is a known bootstrap document.
pub fn isBootstrapFilename(basename: []const u8) bool

comptime {

test "isBootstrapFilename recognizes known files" {
