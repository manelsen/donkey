const std = @import("std");
const Config = @import("config.zig").Config;
const channel_loop = @import("channel_loop.zig");
const channels_root = @import("channels/root.zig");
const telegram = @import("channels/telegram.zig");
const signal = @import("channels/signal.zig");
const max_mod = @import("channels/max.zig");
const agent_routing = @import("agent_routing.zig");



pub const PollingDescriptor = struct {

fn telegramPollingSourceKey(allocator: std.mem.Allocator, channel: channels_root.Channel) ?[]u8

fn signalPollingSourceKey(allocator: std.mem.Allocator, channel: channels_root.Channel) ?[]u8


pub fn findPollingDescriptor(channel_name: []const u8) ?*const PollingDescriptor

pub const InboundMetadata = struct {

pub const InboundRouteInput = struct {

pub const InboundRouteDescriptor = struct {

pub fn parsePeerKind(raw: []const u8) ?agent_routing.ChatType

fn defaultDiscordAccount(config: *const Config, _: []const u8) ?[]const u8

fn defaultSlackAccount(config: *const Config, _: []const u8) ?[]const u8

fn defaultQQAccount(config: *const Config, _: []const u8) ?[]const u8

fn defaultOnebotAccount(config: *const Config, _: []const u8) ?[]const u8

fn defaultIrcAccount(config: *const Config, _: []const u8) ?[]const u8

fn defaultMattermostAccount(config: *const Config, _: []const u8) ?[]const u8

fn defaultIMessageAccount(config: *const Config, _: []const u8) ?[]const u8

fn matchesMaixcam(config: *const Config, channel_name: []const u8) bool

fn defaultMaixcamAccount(config: *const Config, channel_name: []const u8) ?[]const u8

fn stripPrefix(value: []const u8, prefix: []const u8) []const u8

fn deriveDiscordPeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn deriveSlackPeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn deriveQQPeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn deriveOnebotPeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn deriveIrcPeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn deriveMattermostPeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn deriveIMessagePeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn deriveMaixcamPeer(input: InboundRouteInput, _: InboundMetadata) ?agent_routing.PeerRef

fn defaultMaxAccount(config: *const Config, _: []const u8) ?[]const u8

fn deriveMaxPeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn defaultTeamsAccount(config: *const Config, _: []const u8) ?[]const u8

fn deriveTeamsPeer(input: InboundRouteInput, meta: InboundMetadata) ?agent_routing.PeerRef

fn defaultWebAccount(config: *const Config, _: []const u8) ?[]const u8

fn deriveWebPeer(input: InboundRouteInput, _: InboundMetadata) ?agent_routing.PeerRef


pub fn findInboundRouteDescriptor(config: *const Config, channel_name: []const u8) ?*const InboundRouteDescriptor

test "findPollingDescriptor returns known polling adapters" {

test "parsePeerKind handles supported values" {

test "findInboundRouteDescriptor finds web channel" {

test "web inbound routing uses chat session id for peer" {

    const desc = findInboundRouteDescriptor(&cfg, "web") orelse return error.TestUnexpectedResult;


test "findInboundRouteDescriptor supports custom maixcam names" {
