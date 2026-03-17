//! Channel Manager — centralizes channel lifecycle (init, start, supervise, stop).
//!
//! Replaces the hardcoded Telegram/Signal-only logic in daemon.zig with a
//! generic system that handles all configured channels.

const std = @import("std");
const Allocator = std.mem.Allocator;
const bus_mod = @import("bus.zig");
const Config = @import("config.zig").Config;
const config_types = @import("config_types.zig");
const channel_catalog = @import("channel_catalog.zig");
const channel_adapters = @import("channel_adapters.zig");
const dispatch = @import("channels/dispatch.zig");
const channel_loop = @import("channel_loop.zig");
const health = @import("health.zig");
const daemon = @import("daemon.zig");
const channels_mod = @import("channels/root.zig");
const mattermost = channels_mod.mattermost;
const discord = channels_mod.discord;
const dingtalk = channels_mod.dingtalk;
const imessage = channels_mod.imessage;
const qq = channels_mod.qq;
const onebot = channels_mod.onebot;
const maixcam = channels_mod.maixcam;
const slack = channels_mod.slack;
const irc = channels_mod.irc;
const web = channels_mod.web;
const Channel = channels_mod.Channel;

const log = std.log.scoped(.channel_manager);

pub const ListenerType = enum {
    /// Telegram, Signal — poll in a loop
    /// Discord, Mattermost, Slack, IRC, QQ(websocket), OneBot — internal socket/WebSocket loop
    /// WhatsApp, Line, Lark — HTTP gateway receives
    /// Outbound-only channel lifecycle (start/stop/send, no inbound listener thread yet)
    /// Channel exists but no listener yet

pub const Entry = struct {

pub const PollingState = channel_loop.PollingState;

pub const ChannelManager = struct {

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "PollingState has telegram signal matrix and max variants" {

test "ListenerType enum values distinct" {

test "isPollingSourceDuplicate detects duplicate signal source" {
    const allocator = std.testing.allocator;


    var sup_a = dispatch.spawnSupervisedChannel(sig_a.channel(), 5);
    const sup_b = dispatch.spawnSupervisedChannel(sig_b.channel(), 5);


    const desc = channel_adapters.findPollingDescriptor("signal").?;

test "isPollingSourceDuplicate ignores distinct signal source" {
    const allocator = std.testing.allocator;


    var sup_a = dispatch.spawnSupervisedChannel(sig_a.channel(), 5);
    const sup_b = dispatch.spawnSupervisedChannel(sig_b.channel(), 5);


    const desc = channel_adapters.findPollingDescriptor("signal").?;

test "isPollingSourceDuplicate detects duplicate telegram source" {
    const allocator = std.testing.allocator;


    var sup_a = dispatch.spawnSupervisedChannel(tg_a.channel(), 5);
    const sup_b = dispatch.spawnSupervisedChannel(tg_b.channel(), 5);


    const desc = channel_adapters.findPollingDescriptor("telegram").?;

test "isPollingSourceDuplicate ignores distinct telegram source" {
    const allocator = std.testing.allocator;


    var sup_a = dispatch.spawnSupervisedChannel(tg_a.channel(), 5);
    const sup_b = dispatch.spawnSupervisedChannel(tg_b.channel(), 5);


    const desc = channel_adapters.findPollingDescriptor("telegram").?;

test "ChannelManager init and deinit" {
    const allocator = std.testing.allocator;
    var reg = dispatch.ChannelRegistry.init(allocator);
    const mgr = try ChannelManager.init(allocator, &config, &reg);

test "ChannelManager no channels configured" {
    const allocator = std.testing.allocator;
    var reg = dispatch.ChannelRegistry.init(allocator);
    const mgr = try ChannelManager.init(allocator, &config, &reg);


fn countEntriesByListenerType(entries: []const Entry, listener_type: ListenerType) usize

fn findEntryByNameAccount(entries: []const Entry, name: []const u8, account_id: []const u8) ?*const Entry

fn expectEntryPresence(entries: []const Entry, name: []const u8, account_id: []const u8, should_exist: bool) !void

test "ChannelManager collectConfiguredChannels wires listener types accounts and bus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();

    const slack_allow = [_][]const u8{

test "ChannelManager marks qq webhook receive_mode as webhook_only" {

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();



    var reg = dispatch.ChannelRegistry.init(allocator);

    const mgr = try ChannelManager.init(allocator, &config, &reg);


test "ChannelManager marks lark websocket receive_mode as gateway_loop" {

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();



    var reg = dispatch.ChannelRegistry.init(allocator);

    const mgr = try ChannelManager.init(allocator, &config, &reg);


test "ChannelManager marks lark webhook receive_mode as webhook_only" {

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();



    var reg = dispatch.ChannelRegistry.init(allocator);

    const mgr = try ChannelManager.init(allocator, &config, &reg);


test "ChannelManager collects web channel from config" {

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();



    var reg = dispatch.ChannelRegistry.init(allocator);

    var event_bus = bus_mod.Bus.init();

    const mgr = try ChannelManager.init(allocator, &config, &reg);



    // Verify it was registered with correct listener type
    const web_entry = findEntryByNameAccount(mgr.channelEntries(), "web", "local").?;

    const web_ptr: *web.WebChannel = @ptrCast(@alignCast(web_entry.channel.ptr));
