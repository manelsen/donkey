const std = @import("std");
const Sandbox = @import("sandbox.zig").Sandbox;

/// Bubblewrap (bwrap) sandbox backend.
/// Wraps commands with `bwrap` for user-namespace isolation.
pub const BubblewrapSandbox = struct {

pub fn createBubblewrapSandbox(workspace_dir: []const u8) BubblewrapSandbox

// ── Tests ──────────────────────────────────────────────────────────────

test "bubblewrap sandbox name" {
    var bw = createBubblewrapSandbox("/tmp/workspace");
    const sb = bw.sandbox();

test "bubblewrap sandbox description mentions bwrap" {
    var bw = createBubblewrapSandbox("/tmp/workspace");
    const sb = bw.sandbox();
    const desc = sb.description();

test "bubblewrap sandbox wrap command prepends bwrap args" {
    var bw = createBubblewrapSandbox("/tmp/workspace");
    const sb = bw.sandbox();

    const argv = [_][]const u8{

test "bubblewrap sandbox wrap includes unshare and die-with-parent" {
    var bw = createBubblewrapSandbox("/tmp/workspace");
    const sb = bw.sandbox();

    const argv = [_][]const u8{

test "bubblewrap sandbox wrap empty argv" {
    var bw = createBubblewrapSandbox("/tmp/workspace");
    const sb = bw.sandbox();

    const argv = [_][]const u8{

test "bubblewrap buffer too small returns error" {
    var bw = createBubblewrapSandbox("/tmp/workspace");
    const sb = bw.sandbox();

    const argv = [_][]const u8{
