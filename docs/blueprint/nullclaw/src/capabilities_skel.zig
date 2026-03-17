const std = @import("std");
const build_options = @import("build_options");
const channel_catalog = @import("channel_catalog.zig");
const config_mod = @import("config.zig");
const memory_registry = @import("memory/engines/registry.zig");
const tools_mod = @import("tools/root.zig");

const Config = config_mod.Config;
const Tool = tools_mod.Tool;



const ChannelMode = enum {

const EngineMode = enum {

const OptionalToolMode = enum {

fn runtimeHasTool(runtime_tools: ?[]const Tool, name: []const u8) bool

fn optionalToolEnabledByConfig(cfg: *const Config, name: []const u8) bool

    var out: std.ArrayListUnmanaged([]const u8) = .empty;

        const enabled = channel_catalog.isBuildEnabled(meta.id);
        const configured = if (cfg_opt) |cfg| channel_catalog.configuredCount(cfg, meta.id) > 0 else false;


fn collectMemoryEngineNames(allocator: std.mem.Allocator, mode: EngineMode) ![]const []const u8

    var out: std.ArrayListUnmanaged([]const u8) = .empty;


        const enabled = optionalToolEnabledByConfig(cfg, name);


        var out: std.ArrayListUnmanaged([]const u8) = .empty;

    var estimated: std.ArrayListUnmanaged([]const u8) = .empty;
    const optional_enabled = try collectOptionalTools(allocator, cfg_opt, .enabled);

fn joinNames(allocator: std.mem.Allocator, names: []const []const u8) ![]u8

fn appendJsonStringArray(w: anytype, names: []const []const u8) !void



    var out: std.ArrayListUnmanaged(u8) = .empty;
    const w = out.writer(allocator);


    const memory_backend = if (cfg_opt) |cfg| cfg.memory.backend else "";

        const enabled = channel_catalog.isBuildEnabled(meta.id);
        const configured_count: usize = if (cfg_opt) |cfg| channel_catalog.configuredCount(cfg, meta.id) else 0;
        const configured = enabled and configured_count > 0;

        const enabled = memory_registry.findBackend(name) != null;
        const configured = cfg_opt != null and std.mem.eql(u8, cfg_opt.?.memory.backend, name);



    const optional_enabled = try collectOptionalTools(allocator, cfg_opt, .enabled);
    const optional_disabled = try collectOptionalTools(allocator, cfg_opt, .disabled);




    const channels_enabled = try collectChannelNames(allocator, cfg_opt, .build_enabled);
    const channels_disabled = try collectChannelNames(allocator, cfg_opt, .build_disabled);
    const channels_configured = try collectChannelNames(allocator, cfg_opt, .configured);

    const engines_enabled = try collectMemoryEngineNames(allocator, .build_enabled);
    const engines_disabled = try collectMemoryEngineNames(allocator, .build_disabled);

    const runtime_tool_names = try collectRuntimeToolNames(allocator, cfg_opt, runtime_tools);
    const optional_disabled = try collectOptionalTools(allocator, cfg_opt, .disabled);

    const channels_enabled_s = try joinNames(allocator, channels_enabled);
    const channels_disabled_s = try joinNames(allocator, channels_disabled);
    const channels_configured_s = try joinNames(allocator, channels_configured);
    const engines_enabled_s = try joinNames(allocator, engines_enabled);
    const engines_disabled_s = try joinNames(allocator, engines_disabled);
    const runtime_tools_s = try joinNames(allocator, runtime_tool_names);
    const optional_disabled_s = try joinNames(allocator, optional_disabled);

    const active_backend = if (cfg_opt) |cfg| cfg.memory.backend else "(unknown)";
    const tools_label = if (runtime_tools != null) "tools (loaded)" else "tools (estimated from config)";


    const channels_enabled = try collectChannelNames(allocator, cfg_opt, .build_enabled);
    const channels_disabled = try collectChannelNames(allocator, cfg_opt, .build_disabled);
    const channels_configured = try collectChannelNames(allocator, cfg_opt, .configured);

    const engines_enabled = try collectMemoryEngineNames(allocator, .build_enabled);
    const engines_disabled = try collectMemoryEngineNames(allocator, .build_disabled);

    const runtime_tool_names = try collectRuntimeToolNames(allocator, cfg_opt, runtime_tools);
    const optional_disabled = try collectOptionalTools(allocator, cfg_opt, .disabled);

    const channels_enabled_s = try joinNames(allocator, channels_enabled);
    const channels_disabled_s = try joinNames(allocator, channels_disabled);
    const channels_configured_s = try joinNames(allocator, channels_configured);
    const engines_enabled_s = try joinNames(allocator, engines_enabled);
    const engines_disabled_s = try joinNames(allocator, engines_disabled);
    const runtime_tools_s = try joinNames(allocator, runtime_tool_names);
    const optional_disabled_s = try joinNames(allocator, optional_disabled);

    const active_backend = if (cfg_opt) |cfg| cfg.memory.backend else "(unknown)";


test "buildManifestJson emits core sections" {
    const manifest = try buildManifestJson(std.testing.allocator, null, null);


test "buildManifestJson includes runtime_loaded when runtime tools are unavailable" {
    const manifest = try buildManifestJson(std.testing.allocator, null, null);


test "buildSummaryText includes availability sections" {
    const summary = try buildSummaryText(std.testing.allocator, null, null);

