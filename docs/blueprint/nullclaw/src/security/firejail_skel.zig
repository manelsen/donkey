const std = @import("std");
const Sandbox = @import("sandbox.zig").Sandbox;

/// Firejail sandbox backend for Linux.
/// Wraps commands with `firejail` for user-space sandboxing.
pub const FirejailSandbox = struct {

pub fn createFirejailSandbox(workspace_dir: []const u8) FirejailSandbox

// ── Tests ──────────────────────────────────────────────────────────────

test "firejail sandbox name" {
    var fj = createFirejailSandbox("/tmp/workspace");
    const sb = fj.sandbox();

test "firejail sandbox wrap command prepends firejail args" {
    var fj = createFirejailSandbox("/tmp/workspace");
    const sb = fj.sandbox();

    const argv = [_][]const u8{

test "firejail sandbox wrap empty argv" {
    var fj = createFirejailSandbox("/tmp/workspace");
    const sb = fj.sandbox();

    const argv = [_][]const u8{

test "firejail sandbox wrap single arg" {
    var fj = createFirejailSandbox("/tmp/workspace");
    const sb = fj.sandbox();

    const argv = [_][]const u8{

test "firejail buffer too small returns error" {
    var fj = createFirejailSandbox("/tmp/workspace");
    const sb = fj.sandbox();

    const argv = [_][]const u8{
