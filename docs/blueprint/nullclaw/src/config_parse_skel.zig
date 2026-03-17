const std = @import("std");
const types = @import("config_types.zig");
const agent_routing = @import("agent_routing.zig");

const log = std.log.scoped(.config);

// Forward-reference to the Config struct defined in config.zig.
// Zig handles circular @import lazily, so this works as long as there is
// no comptime-initialization cycle.
const config_mod = @import("config.zig");
const Config = config_mod.Config;

/// Parse a JSON array of strings into an allocated slice.
pub fn parseStringArray(allocator: std.mem.Allocator, arr: std.json.Array) ![]const []const u8

fn parseApiKeyField(allocator: std.mem.Allocator, value: std.json.Value) !?[]const u8

const PrimaryModelRef = struct {

fn freeNamedAgentConfig(allocator: std.mem.Allocator, agent_cfg: *types.NamedAgentConfig) void

fn splitPrimaryModelRef(primary: []const u8) ?PrimaryModelRef


    const provider_val = item.object.get("provider");
        const m = item.object.get("model") orelse break :blk null;


            const val = sp.string;

fn parsePeerKind(kind: []const u8) ?agent_routing.ChatType

fn parseModelRouteCostClass(raw: []const u8) ?types.ModelRouteCostClass

fn parseModelRouteQuotaClass(raw: []const u8) ?types.ModelRouteQuotaClass

fn freeModelRouteConfig(allocator: std.mem.Allocator, route: types.ModelRouteConfig) void

/// Normalize a peer ID from config: convert legacy `#topic:N` format to
/// canonical `:thread:N` format used internally for route matching.
/// Logs a deprecation warning when conversion occurs.
fn normalizePeerId(allocator: std.mem.Allocator, raw_id: []const u8) ![]u8

    var list: std.ArrayListUnmanaged(agent_routing.AgentBinding) = .empty;


        const agent_id_val = item.object.get("agent_id") orelse continue;



        const match_val = item.object.get("match");
                        const kind_val = peer_val.object.get("kind");
                        const id_val = peer_val.object.get("id");



const SelectedAccount = struct {

fn countAccounts(accounts: std.json.ObjectMap) usize

fn getPreferredAccount(channel_obj: std.json.ObjectMap) ?SelectedAccount

fn getAllAccountsSorted(allocator: std.mem.Allocator, channel_obj: std.json.ObjectMap) ![]const SelectedAccount

fn parseTypedValue(comptime T: type, allocator: std.mem.Allocator, value: std.json.Value) ?T

fn maybeSetAccountId(comptime T: type, allocator: std.mem.Allocator, parsed: *T, account_id: []const u8) !void

fn parseMultiAccountChannel(comptime T: type, allocator: std.mem.Allocator, channel_value: std.json.Value) ![]const T

fn parseSingleAccountChannel(comptime T: type, allocator: std.mem.Allocator, channel_value: std.json.Value) !?T

fn parseInlineChannel(comptime T: type, allocator: std.mem.Allocator, channel_value: std.json.Value) ?T

fn parseChannels(self: *Config, channels_value: std.json.Value) !void

/// Parse JSON content into the given Config.
pub fn parseJson(self: *Config, content: []const u8) !void

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "normalizePeerId converts legacy #topic: format to canonical :thread: format" {
    const allocator = std.testing.allocator;

    // Legacy #topic: format should be converted
    const converted = try normalizePeerId(allocator, "-1009999999999#topic:4");

    // Canonical :thread: format should pass through unchanged
    const canonical = try normalizePeerId(allocator, "-1009999999999:thread:4");

    // Plain peer ID without topic should pass through unchanged
    const plain = try normalizePeerId(allocator, "-1009999999999");

    // Direct chat ID should pass through unchanged
    const direct = try normalizePeerId(allocator, "5555555555");

test "parseAgentBindingsArray normalizes legacy #topic: peer IDs" {
    const allocator = std.testing.allocator;


    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{
