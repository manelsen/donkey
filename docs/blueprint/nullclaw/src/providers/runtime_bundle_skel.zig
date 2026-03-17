const std = @import("std");
const Config = @import("../config.zig").Config;
const factory = @import("factory.zig");
const ProviderHolder = factory.ProviderHolder;
const Provider = @import("root.zig").Provider;
const reliable = @import("reliable.zig");
const router = @import("router.zig");
const api_key = @import("api_key.zig");

const HolderPlan = struct {

fn trimOptionalKey(raw_key: ?[]const u8) ?[]const u8



fn keysMatch(existing_key: ?[]const u8, raw_override: ?[]const u8) bool


/// Runtime provider wiring with optional reliability wrapper.
///
/// Owns:
/// - primary provider holder
/// - optional router-specific provider holders and router wrapper
/// - optional fallback provider holders
/// - optional ReliableProvider wrapper
/// - any resolved API keys allocated during provider resolution
pub const RuntimeProviderBundle = struct {

test "RuntimeProviderBundle init/deinit without reliability wrapper" {

    var bundle = try RuntimeProviderBundle.init(std.testing.allocator, &cfg);


test "RuntimeProviderBundle init/deinit with fallback providers and model fallbacks" {


    var bundle = try RuntimeProviderBundle.init(std.testing.allocator, &cfg);


test "RuntimeProviderBundle turns reliability api_keys into fallback providers" {

    var bundle = try RuntimeProviderBundle.init(std.testing.allocator, &cfg);


test "RuntimeProviderBundle builds router-backed provider when model routes are configured" {

    var bundle = try RuntimeProviderBundle.init(std.testing.allocator, &cfg);

