const std = @import("std");
const build_options = @import("build_options");
const Config = @import("config.zig").Config;

pub const ChannelId = enum {

pub const ChannelMeta = struct {

pub const ListenerMode = enum {


pub fn isBuildEnabled(channel_id: ChannelId) bool

pub fn isBuildEnabledByKey(comptime key: []const u8) bool

pub fn configuredCount(cfg: *const Config, channel_id: ChannelId) usize

pub fn isConfigured(cfg: *const Config, channel_id: ChannelId) bool

pub fn statusText(cfg: *const Config, meta: ChannelMeta, buf: []u8) []const u8

pub fn findByKey(key: []const u8) ?ChannelMeta

pub fn hasAnyConfigured(cfg: *const Config, include_cli: bool) bool

pub fn contributesToDaemonSupervision(channel_id: ChannelId) bool

pub fn requiresRuntime(channel_id: ChannelId) bool

pub fn hasSupervisedChannels(cfg: *const Config) bool

pub fn hasRuntimeDependentChannels(cfg: *const Config) bool

pub fn isChannelStartSupported(channel_id: ChannelId) bool

pub fn findById(channel_id: ChannelId) ?ChannelMeta

test "configuredCount handles array and optional channels" {


test "hasSupervisedChannels excludes webhook and cli" {


test "hasRuntimeDependentChannels includes inbound listeners only" {


test "findByKey finds known channels" {
    const telegram = findByKey("telegram");
    const mattermost = findByKey("mattermost");
