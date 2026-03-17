const std = @import("std");
const Config = @import("config.zig").Config;
const config_types = @import("config_types.zig");
const agent_routing = @import("agent_routing.zig");


pub const BindingTarget = struct {

pub const BindingLookupScope = enum {

pub const BindingLookup = struct {

pub const BindingUpdateStatus = enum {

pub const BindingUpdateResult = struct {

fn dupOptionalString(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8

fn dupStringSlice(allocator: std.mem.Allocator, src: []const []const u8) ![]const []const u8

fn freeStringSlice(allocator: std.mem.Allocator, src: []const []const u8) void

pub fn freeBinding(allocator: std.mem.Allocator, binding: *const agent_routing.AgentBinding) void

pub fn freeBindingSlice(allocator: std.mem.Allocator, bindings: []const agent_routing.AgentBinding) void


fn dupBinding(allocator: std.mem.Allocator, binding: agent_routing.AgentBinding) !agent_routing.AgentBinding


fn bindingHasOnlyPeerScope(binding: agent_routing.AgentBinding) bool

fn optionalEql(a: ?[]const u8, b: ?[]const u8) bool

fn bindingMatchesTarget(binding: agent_routing.AgentBinding, target: BindingTarget, scope: BindingLookupScope) bool





    const previous_bindings = cfg.agent_bindings;
    const previous_owned = cfg.agent_bindings_runtime_owned;

    const owned = cfg.agent_bindings;

    const trimmed = std.mem.trim(u8, requested, " \t\r\n");


    var req_buf: [64]u8 = undefined;
    const normalized_requested = agent_routing.normalizeId(&req_buf, trimmed);
        var agent_buf: [64]u8 = undefined;
        const normalized_agent = agent_routing.normalizeId(&agent_buf, agent.name);


        var agent_buf: [64]u8 = undefined;
        const normalized_agent = agent_routing.normalizeId(&agent_buf, agent.name);

    const existing = findExactPeerBinding(cfg.agent_bindings, target);

        const profile = findNamedAgent(cfg.agents, raw_agent) orelse return error.UnknownAgent;
        var agent_buf: [64]u8 = undefined;
        const normalized_agent_id = agent_routing.normalizeId(&agent_buf, profile.name);


        var desired = try buildManagedBinding(allocator, target, normalized_agent_id);
        var desired_owned = true;

        var next: std.ArrayListUnmanaged(agent_routing.AgentBinding) = .empty;



    const current = existing orelse return .{

fn loadConfigFromPath(allocator: std.mem.Allocator, config_path: []const u8) !Config

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    const arena = arena_state.allocator();

    var cfg = try loadConfigFromPath(arena, config_path);
    const result = try applyBindingUpdate(arena, &cfg, target, requested_agent);

test "findNamedAgent accepts normalized id alias" {

    const found = findNamedAgent(&agents, "coder-agent") orelse return error.TestExpectedEqual;

test "applyBindingUpdate adds account-scoped peer binding" {



test "applyBindingUpdate adds exact binding without replacing inherited peer fallback" {
    const allocator = std.testing.allocator;
    const existing = try allocator.alloc(agent_routing.AgentBinding, 1);






test "applyBindingUpdate clear removes exact binding only" {
    const allocator = std.testing.allocator;
    const existing = try allocator.alloc(agent_routing.AgentBinding, 1);




test "applyBindingUpdate clear keeps inherited unscoped peer binding" {
    const allocator = std.testing.allocator;
    const existing = try allocator.alloc(agent_routing.AgentBinding, 1);




test "persistBindingUpdate skips rewriting config when binding is unchanged" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{
