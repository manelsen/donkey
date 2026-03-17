//! Self-update command for nullclaw.
//!
//! Checks GitHub releases for updates and provides an automated
//! update path for binary installations.

const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.update);

// ── Public API ───────────────────────────────────────────────────────

pub const Options = struct {

pub fn run(allocator: std.mem.Allocator, opts: Options) !void

// ── Install Detection ─────────────────────────────────────────────────

pub const InstallMethod = enum {

pub fn detectInstallMethod() !InstallMethod

fn printPackageManagerUpdate(method: InstallMethod) !void

// ── GitHub API ────────────────────────────────────────────────────────

pub const ReleaseInfo = struct {

pub fn getLatestRelease(allocator: std.mem.Allocator) !ReleaseInfo

// ── Version Comparison ────────────────────────────────────────────────

fn stripV(v: []const u8) []const u8

// ── Platform Detection ────────────────────────────────────────────────

pub const PlatformTarget = enum {

fn platformFromParts(os: std.Target.Os.Tag, arch: std.Target.Cpu.Arch) ?PlatformTarget

pub fn getCurrentPlatform() ?PlatformTarget

// ── Asset URL Finding ─────────────────────────────────────────────────

fn findAssetUrl(allocator: std.mem.Allocator, asset_name: []const u8) ?[]const u8

// ── Download & Install ────────────────────────────────────────────────


    // Create temp file first
    const tmp_path = try std.fmt.allocPrint(allocator, "{

/// Download a URL directly to a file using curl.
/// Streams the data to avoid memory buffer limits.
/// Returns the number of bytes downloaded.
fn downloadToFile(allocator: std.mem.Allocator, url: []const u8, file: *std.fs.File) !usize

fn atomicReplace(tmp_path: []const u8, exe_path: []const u8) !void

// ── User Input ────────────────────────────────────────────────────────

fn readLine(allocator: std.mem.Allocator) ![]const u8

// ── Tests ────────────────────────────────────────────────────────────

test "detectInstallMethod" {
    const method = try detectInstallMethod();
    // Should at least not crash

test "getCurrentPlatform" {
    const platform = getCurrentPlatform();
    // Should return null or a valid platform for this system

test "stripV" {

test "PlatformTarget.assetName covers all release assets" {

test "platformFromParts maps supported and unsupported targets" {


test "downloadToFile streams from local file URL" {

    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{
