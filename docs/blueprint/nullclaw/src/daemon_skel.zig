//! Daemon — main event loop with component supervision.
//!
//! Mirrors ZeroClaw's daemon module:
//!   - Spawns gateway, channels, heartbeat, scheduler
//!   - Exponential backoff on component failure
//!   - Periodic state file writing (daemon_state.json)
//!   - Ctrl+C graceful shutdown

const std = @import("std");
const health = @import("health.zig");
const Config = @import("config.zig").Config;
const CronScheduler = @import("cron.zig").CronScheduler;
const cron = @import("cron.zig");
const bus_mod = @import("bus.zig");
const channels_mod = @import("channels/root.zig");
const dispatch = @import("channels/dispatch.zig");
const channel_loop = @import("channel_loop.zig");
const channel_manager = @import("channel_manager.zig");
const agent_routing = @import("agent_routing.zig");
const channel_catalog = @import("channel_catalog.zig");
const channel_adapters = @import("channel_adapters.zig");
const heartbeat_mod = @import("heartbeat.zig");
const interaction_choices = @import("interactions/choices.zig");
const memory_mod = @import("memory/root.zig");
const bootstrap_mod = @import("bootstrap/root.zig");
const onboard = @import("onboard.zig");
const streaming = @import("streaming.zig");
const ConversationContext = @import("agent/prompt.zig").ConversationContext;
const thread_stacks = @import("thread_stacks.zig");
const tunnel_mod = @import("tunnel.zig");

const log = std.log.scoped(.daemon);

/// How often the daemon state file is flushed (seconds).
const STATUS_FLUSH_SECONDS: u64 = 5;

/// Daemon heartbeat initializes memory/bootstrap runtime state before it
/// settles into its periodic loop, so it needs the session-turn budget.
const HEARTBEAT_THREAD_STACK_SIZE: usize = thread_stacks.SESSION_TURN_STACK_SIZE;

/// Maximum number of supervised components.
const MAX_COMPONENTS: usize = 8;

/// Component status for state file serialization.
pub const ComponentStatus = struct {

/// Daemon state written to daemon_state.json periodically.
pub const DaemonState = struct {

/// Compute the path to daemon_state.json from config.
pub fn stateFilePath(allocator: std.mem.Allocator, config: *const Config) ![]u8

/// Write daemon state to disk as JSON.
pub fn writeStateFile(allocator: std.mem.Allocator, path: []const u8, state: *const DaemonState) !void

/// Compute exponential backoff duration.
pub fn computeBackoff(current_backoff: u64, max_backoff: u64) u64

/// Check if any real-time channels are configured.
pub fn hasSupervisedChannels(config: *const Config) bool

/// Shutdown signal — set to true to stop the daemon.
var shutdown_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Request a graceful shutdown of the daemon.
pub fn requestShutdown() void

/// Check if shutdown has been requested.
pub fn isShutdownRequested() bool

fn recordGatewayFailure(err: anyerror, state: *DaemonState) void

fn logGatewayFailure(err: anyerror, port: u16) void

/// Gateway thread entry point.
fn gatewayThread(allocator: std.mem.Allocator, config: *const Config, host: []const u8, port: u16, state: *DaemonState, event_bus: *bus_mod.Bus) void

/// Heartbeat thread — periodically writes state file, checks health, and
/// runs HEARTBEAT.md polling ticks on the configured heartbeat interval.
fn heartbeatThread(allocator: std.mem.Allocator, config: *const Config, state: *DaemonState) void

/// How often the channel watcher checks health (seconds).
const CHANNEL_WATCH_INTERVAL_SECS: u64 = 60;

/// Initial backoff for scheduler restarts (seconds).
/// Kept for compatibility with existing tests and supervision semantics.
const SCHEDULER_INITIAL_BACKOFF_SECS: u64 = 1;

/// Maximum backoff for scheduler restarts (seconds).
/// Kept for compatibility with existing tests and supervision semantics.
const SCHEDULER_MAX_BACKOFF_SECS: u64 = 60;

const SchedulerJobSnapshot = struct {

fn schedulerStatusEquals(a: ?[]const u8, b: ?[]const u8) bool

fn schedulerJobChanged(job: *const cron.CronJob, snapshot: SchedulerJobSnapshot) bool

    var it = snapshot.iterator();

        const key = try allocator.dupe(u8, job.id);

        // Update delivery config


    var latest = CronScheduler.init(allocator, runtime.max_tasks, runtime.enabled);

    var runtime_ids: std.StringHashMapUnmanaged(void) = .empty;


    var removed_it = before_tick.iterator();
        const job_id = entry.key_ptr.*;


/// Scheduler thread — executes due cron jobs and periodically reloads cron.json
/// so tasks created/updated after daemon startup are picked up without restart.
fn schedulerThread(allocator: std.mem.Allocator, config: *const Config, state: *DaemonState, event_bus: *bus_mod.Bus) void

/// Channel supervisor thread — spawns polling threads for configured channels,
/// monitors their health, and restarts on failure using SupervisedChannel.
    // Early exit if shutdown was requested before channel startup.






/// Inbound dispatcher thread:
/// consumes inbound events from channels, runs SessionManager, publishes outbound replies.
const ParsedInboundMetadata = struct {

fn parseInboundMetadata(allocator: std.mem.Allocator, metadata_json: ?[]const u8) ParsedInboundMetadata

    const route_desc = channel_adapters.findInboundRouteDescriptor(config, msg.channel);



        const topic_peer_id = std.fmt.allocPrint(allocator, "{


        const threaded = agent_routing.buildThreadSessionKey(allocator, route.session_key, thread_id) catch return route.session_key;

    var parsed_meta = parseInboundMetadata(allocator, msg.metadata_json);

const SlackStatusTarget = struct {

fn resolveSlackStatusTarget(meta: channel_adapters.InboundMetadata, chat_id: []const u8) ?SlackStatusTarget

        const slack_target = resolveSlackStatusTarget(meta, chat_id) orelse return null;


    const ch = channel_opt orelse return null;

    const recipient = resolveTypingRecipient(allocator, channel_name, chat_id, meta) orelse return null;

    const target = recipient orelse return;
    const ch = channel_opt orelse return;

const StreamingOutboundCtx = struct {

fn publishStreamingChunk(ctx_ptr: *anyopaque, event: streaming.Event) void

fn supportsStreamingOutbound(channel: []const u8) bool


    var parsed = try interaction_choices.parseAssistantChoices(allocator, reply);




    var evict_counter: u32 = 0;


        var parsed_meta = parseInboundMetadata(allocator, msg.metadata_json);

        const outbound_account_id = parsed_meta.fields.account_id;
        const session_key = routed_session_key orelse msg.session_key;


        const use_streaming_outbound = supportsStreamingOutbound(msg.channel);
        var stream_sink: ?streaming.Sink = null;
        var outbound_tag_filter: streaming.TagFilter = undefined;


        // Build conversation context for channels that provide sender metadata.
        // Discord passes sender info via metadata JSON; Signal/Telegram do it in channel_loop.


            // Send user-visible error reply back to the originating channel




        // Periodic session eviction for bus-based channels





/// Run the long-lived runtime. This is the main entry point for `nullclaw gateway`.
/// Spawns threads for gateway, heartbeat, and channels, then loops until
/// shutdown is requested (Ctrl+C signal or explicit request).
/// `host` and `port` are CLI-parsed values that override `config.gateway`.
pub fn run(allocator: std.mem.Allocator, config: *const Config, host: []const u8, port: u16) !void

// ── Tests ────────────────────────────────────────────────────────

test "DaemonState addComponent" {
    var state = DaemonState{

test "DaemonState markError and markRunning" {
    var state = DaemonState{

test "computeBackoff doubles up to max" {

test "computeBackoff saturating" {

test "makeStreamingSinkForChannel filters web chunks" {
    const Collector = struct {

    var collector = Collector{

test "makeStreamingSinkForChannel supports dingtalk" {
    const Noop = struct {

    var filter: streaming.TagFilter = undefined;

test "makeStreamingSinkForChannel returns null for unsupported channel" {
    const Noop = struct {

    var filter: streaming.TagFilter = undefined;

test "hasSupervisedChannels false for defaults" {

test "resolveInboundRouteSessionKey falls back to configured account_id" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes onebot group messages by group id" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey prefers metadata account_id override" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey supports custom maixcam channel name" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey matches non-primary maixcam account by channel name" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes discord channel messages by chat_id" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes discord direct messages by sender" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey applies session dm_scope for direct messages" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey normalizes qq channel prefix for routed peer id" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes slack channel messages by chat_id" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes threaded slack channel messages by base channel_id" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes slack direct messages by sender" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes qq dm messages by sender id" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes irc channel messages by chat id" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes irc direct messages by sender" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey routes mattermost by channel id and team" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey appends mattermost thread suffix" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey supports standardized peer metadata for unknown channel" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "resolveInboundRouteSessionKey uses telegram thread metadata for topic routing" {
    const allocator = std.testing.allocator;

    const routed = resolveInboundRouteSessionKey(allocator, &config, &msg);

test "parseInboundMetadata extracts message_id and thread_id" {


test "parseInboundMetadata extracts discord sender identity fields" {


test "makeAssistantReplyOutbound preserves plain replies without choices" {
    const allocator = std.testing.allocator;
    var msg = try makeAssistantReplyOutbound(allocator, "telegram", null, "chat1", "hello");


test "makeAssistantReplyOutbound extracts structured choices from assistant reply" {
    const allocator = std.testing.allocator;
    var msg = try makeAssistantReplyOutbound(allocator, "telegram", "backup", "chat1", reply);


test "resolveSlackStatusTarget prefers thread_id then falls back to message_id" {


test "hasSupervisedChannels true for nostr" {
    const config_types = @import("config_types.zig");

test "stateFilePath derives from config_path" {
    const path = try stateFilePath(std.testing.allocator, &config);
    const expected = try std.fs.path.join(std.testing.allocator, &.{

test "scheduler backoff constants" {

test "scheduler backoff progression" {
    var backoff: u64 = SCHEDULER_INITIAL_BACKOFF_SECS;

test "mergeSchedulerTickChangesAndSave preserves externally added jobs" {
    const allocator = std.testing.allocator;
    const cmd_runtime = "echo merge_runtime_keep_7d1c";
    const cmd_external = "echo merge_external_add_9a42";

    var runtime = CronScheduler.init(allocator, 32, true);

    var loaded = CronScheduler.init(allocator, 32, true);

    var before_tick: std.StringHashMapUnmanaged(SchedulerJobSnapshot) = .empty;

    // Simulate concurrent writer adding a new job after scheduler reload.
    var external = CronScheduler.init(allocator, 32, true);


    var merged = CronScheduler.init(allocator, 64, true);

    var found_runtime = false;
    var found_external = false;

test "daemon heartbeat thread stack matches session turn budget" {

test "mergeSchedulerTickChangesAndSave preserves runtime agent fields" {
    const allocator = std.testing.allocator;

    var runtime = CronScheduler.init(allocator, 32, true);

    var loaded = CronScheduler.init(allocator, 32, true);

    var before_tick: std.StringHashMapUnmanaged(SchedulerJobSnapshot) = .empty;

    // Simulate concurrent rewrite removing jobs from disk; merge should restore
    // runtime job with all agent fields.
    var external = CronScheduler.init(allocator, 32, true);


    var merged = CronScheduler.init(allocator, 32, true);

    const job = merged.listJobs()[0];

test "channelSupervisorThread respects shutdown" {
    // Pre-request shutdown so the supervisor exits immediately

    // Config with no telegram → supervisor goes straight to idle loop → exits on shutdown

    var state = DaemonState{

test "recordGatewayFailure requests shutdown for fatal gateway errors" {

    var state = DaemonState{

test "DaemonState supports all supervised components" {
    var state = DaemonState{

test "writeStateFile produces valid content" {

    // Write to a temp path
    var tmp = std.testing.tmpDir(.{

test "writeStateFile includes tunnel fields" {

    var tmp = std.testing.tmpDir(.{

test "writeStateFile handles null tunnel_url" {

    var tmp = std.testing.tmpDir(.{

test "startConfiguredTunnel skips none provider" {
    var state = DaemonState{

test "startConfiguredTunnel records create failure" {

    var state = DaemonState{

test "markError records AddressInUse for gateway component" {
    var state = DaemonState{
