const std = @import("std");
const config_mod = @import("config.zig");
const codex_support = @import("codex_support.zig");
const onboard = @import("onboard.zig");
const providers = @import("providers/root.zig");

const ProbeResult = struct {

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool

fn isLocalEndpoint(url: []const u8) bool

fn providerRequiresApiKey(provider_name: []const u8, base_url: ?[]const u8) bool

fn runCommandProbe(allocator: std.mem.Allocator, argv: []const []const u8, timeout_secs: u64) !void

fn classifyProbeError(err: anyerror) struct

        const result = codex_support.probeCodexCli(allocator);


        const classified = classifyProbeError(err);


fn writeProbeResult(result: ProbeResult) !void

fn freeChatResponse(allocator: std.mem.Allocator, response: providers.ChatResponse) void

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void

test "providerRequiresApiKey marks local providers as keyless" {

test "classifyProbeError maps rate limits" {
    const classified = classifyProbeError(error.RateLimited);

test "classifyProbeError maps missing binary" {
    const classified = classifyProbeError(error.FileNotFound);

test "classifyProbeError maps probe timeout" {
    const classified = classifyProbeError(error.ComponentProbeTimeout);
