const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("root.zig");
const bus = @import("../bus.zig");
const outbound = @import("../outbound.zig");
const Atomic = @import("../portable_atomic.zig").Atomic;
const thread_stacks = @import("../thread_stacks.zig");

/// Message dispatch — routes incoming ChannelMessages to the agent,
/// routes agent responses back to the originating channel.
///
/// This module replaces the Rust channels/mod.rs orchestration:
/// - start_channels, process_channel_message, build_system_prompt
///
/// Zig doesn't have async/await, so channels will be started
/// synchronously or via thread spawning.
pub const ChannelRegistry = struct {

pub const HealthReport = struct {

/// Build a system prompt with channel context.

// ════════════════════════════════════════════════════════════════════════════
// Outbound Dispatch Loop
// ════════════════════════════════════════════════════════════════════════════

/// Counters for the outbound dispatch loop (all atomic for thread safety).
pub const DispatchStats = struct {

/// Run the outbound dispatch loop. Blocks until the bus is closed.
/// Consumes messages from `bus.consumeOutbound()` and routes them to the
/// appropriate channel via `registry.findByName(msg.channel)`.
///
/// Designed to run in a dedicated thread:
///   `std.Thread.spawn(.{}, runOutboundDispatcher, .{ alloc, &bus, &registry, &stats })`
///
/// The loop exits when `bus.close()` is called and the outbound queue is drained.



fn dispatchOutboundMessage(channel: root.Channel, msg: bus.OutboundMessage) !void

/// Get names of all enabled (registered) channels.
pub fn getEnabledChannelNames(registry: *const ChannelRegistry, allocator: Allocator) ![][]const u8

// ════════════════════════════════════════════════════════════════════════════
// Channel Supervisor
// ════════════════════════════════════════════════════════════════════════════

/// Wraps a Channel with supervision state: restart counting, exponential
/// backoff, and a circuit-breaker that gives up after `max_restarts`.
pub const SupervisedChannel = struct {
    /// Record a channel failure. Increments the restart counter, computes
    /// exponential backoff, and transitions to `restarting` or `gave_up`.

/// Create a SupervisedChannel wrapping the given Channel.
pub fn spawnSupervisedChannel(channel: root.Channel, max_restarts: u32) SupervisedChannel

/// Wrap an array of Channels into heap-allocated SupervisedChannels.
pub fn startAllSupervised(allocator: Allocator, channels: []const root.Channel) ![]SupervisedChannel

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "channel registry init and count" {
    const allocator = std.testing.allocator;
    var reg = ChannelRegistry.init(allocator);

test "channel registry register and find" {
    const allocator = std.testing.allocator;
    var reg = ChannelRegistry.init(allocator);

    var cli_ch = @import("cli.zig").CliChannel.init(allocator);


test "channel registry health check all" {
    const allocator = std.testing.allocator;
    var reg = ChannelRegistry.init(allocator);

    var cli_ch = @import("cli.zig").CliChannel.init(allocator);

    const report = reg.healthCheckAll();

test "channel registry channel names" {
    const allocator = std.testing.allocator;
    var reg = ChannelRegistry.init(allocator);

    var cli_ch = @import("cli.zig").CliChannel.init(allocator);

    const names = try reg.channelNames(allocator);

test "health report all healthy" {
    const report = HealthReport{

test "health report not all healthy" {
    const report = HealthReport{

test "health report empty is not healthy" {
    const report = HealthReport{

test "build system prompt" {
    const allocator = std.testing.allocator;
    const prompt = try buildSystemPrompt(allocator, "Be helpful.", "telegram", "nullclaw");

// ════════════════════════════════════════════════════════════════════════════
// Outbound Dispatch Tests
// ════════════════════════════════════════════════════════════════════════════

/// Mock channel for dispatch tests.
const MockChannel = struct {

const MockRichChannel = struct {

test "DispatchStats init all zero" {
    const stats = DispatchStats{

test "dispatcher routes message to correct channel" {
    const allocator = std.testing.allocator;

    var mock_tg = MockChannel{

test "dispatcher routes chunk stage via sendEvent" {
    const allocator = std.testing.allocator;

    var mock_web = MockChannel{

test "dispatcher falls back to sendEvent when structured choices are not supported" {
    const allocator = std.testing.allocator;

    var mock_tg = MockChannel{

test "dispatcher prefers sendRich for final messages with structured choices" {
    const allocator = std.testing.allocator;

    var mock_tg = MockRichChannel{

test "dispatcher keeps legacy attachment-marker payloads on sendEvent path" {
    const allocator = std.testing.allocator;

    var mock_tg = MockRichChannel{

test "dispatcher routes to matching account when channel has multiple accounts" {
    const allocator = std.testing.allocator;

    var main_tg = MockChannel{

test "dispatcher does not fallback to wrong account when account_id is unknown" {
    const allocator = std.testing.allocator;

    var main_tg = MockChannel{

test "dispatcher increments channel_not_found for unknown channel" {
    const allocator = std.testing.allocator;

    var reg = ChannelRegistry.init(allocator);
    // Empty registry — no channels registered

    var event_bus = bus.Bus.init();
    var stats = DispatchStats{

test "dispatcher increments errors on channel.send failure" {
    const allocator = std.testing.allocator;

    var mock_fail = MockChannel{

test "dispatcher handles multiple messages" {
    const allocator = std.testing.allocator;

    var mock_tg = MockChannel{

test "dispatcher mixed: found, not_found, error" {
    const allocator = std.testing.allocator;

    var mock_ok = MockChannel{

test "dispatcher empty bus returns immediately" {
    const allocator = std.testing.allocator;

    var reg = ChannelRegistry.init(allocator);

    var event_bus = bus.Bus.init();
    var stats = DispatchStats{

test "dispatcher runs in a separate thread" {
    const allocator = std.testing.allocator;

    var mock_tg = MockChannel{

test "dispatcher concurrent producers + single dispatcher" {
    const allocator = std.testing.allocator;

    var mock_ch = MockChannel{

test "getEnabledChannelNames returns registered names" {
    const allocator = std.testing.allocator;

    var mock1 = MockChannel{

// ════════════════════════════════════════════════════════════════════════════
// Channel Supervisor Tests
// ════════════════════════════════════════════════════════════════════════════

test "supervised channel initial state" {
    var mock = MockChannel{

test "supervised channel recordFailure increments and sets restarting" {
    var mock = MockChannel{

test "supervised channel backoff capped at max_backoff_ms" {
    var mock = MockChannel{

test "supervised channel gave_up after max_restarts" {
    var mock = MockChannel{

test "supervised channel recordSuccess resets state" {
    var mock = MockChannel{

test "startAllSupervised wraps channel array" {
    const allocator = std.testing.allocator;

    var mock1 = MockChannel{
