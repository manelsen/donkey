/// --list-models subcommand: output available models for a provider as JSON array.
///
/// Used by nullhub to populate the dynamic model selector during onboarding.
/// Delegates to onboard.fetchModels which handles caching, fallbacks, and API calls.
const std = @import("std");
const onboard = @import("onboard.zig");

fn writeModelsJson(out: *std.Io.Writer, models: []const []const u8) !void

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void

test "run requires --provider flag" {
    // Cannot easily test process.exit in-process; just verify the function signature compiles.
    // The real integration test is: nullclaw --list-models --provider anthropic

test "writeModelsJson escapes model identifiers" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);


    const rendered = aw.writer.buffer[0..aw.writer.end];
