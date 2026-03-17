const std = @import("std");
const builtin = @import("builtin");

const VendoredFileHash = struct {


fn hashWithCanonicalLineEndings(bytes: []const u8) [std.crypto.hash.sha2.Sha256.digest_length]u8

fn readFileAllocCompat(dir: std.fs.Dir, allocator: std.mem.Allocator, sub_path: []const u8, max_bytes: usize) ![]u8

fn verifyVendoredSqliteHashes(b: *std.Build) !void

const ChannelSelection = struct {

fn defaultChannels() ChannelSelection

fn parseChannelsOption(raw: []const u8) !ChannelSelection

const EngineSelection = struct {
    // Base backends
    // Optional backends

fn defaultEngines() EngineSelection

fn parseEnginesOption(raw: []const u8) !EngineSelection

fn envExists(name: []const u8) bool

fn ensureAndroidBuildEnvironment(b: *std.Build) void

pub fn build(b: *std.Build) void
