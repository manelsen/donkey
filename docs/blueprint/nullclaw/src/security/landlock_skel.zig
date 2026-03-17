const std = @import("std");
const builtin = @import("builtin");
const Sandbox = @import("sandbox.zig").Sandbox;

/// Landlock sandbox backend for Linux kernel 5.13+ LSM.
/// Restricts filesystem access using the Landlock kernel interface.
/// On non-Linux platforms, returns error.UnsupportedPlatform.
pub const LandlockSandbox = struct {

pub fn createLandlockSandbox(workspace_dir: []const u8) LandlockSandbox

// ── Tests ──────────────────────────────────────────────────────────────

test "landlock sandbox name" {
    var ll = createLandlockSandbox("/tmp/workspace");
    const sb = ll.sandbox();

test "landlock sandbox availability matches platform" {
    var ll = createLandlockSandbox("/tmp/workspace");
    const sb = ll.sandbox();
    if (comptime builtin.os.tag == .linux) {

test "landlock sandbox wrap command on non-linux returns error" {
    if (comptime builtin.os.tag == .linux) return;
    var ll = createLandlockSandbox("/tmp/workspace");
    const sb = ll.sandbox();
    const argv = [_][]const u8{

test "landlock sandbox wrap command on linux passes through" {
    if (comptime builtin.os.tag != .linux) return;
    var ll = createLandlockSandbox("/tmp/workspace");
    const sb = ll.sandbox();
    const argv = [_][]const u8{
