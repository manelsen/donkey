//! Channel Loop — extracted polling loops for daemon-supervised channels.
//!
//! Contains `ChannelRuntime` (shared dependencies for message processing)
//! and `runTelegramLoop` (the polling thread function spawned by the
//! daemon supervisor).

const std = @import("std");
const Config = @import("config.zig").Config;
const config_types = @import("config_types.zig");
const telegram = @import("channels/telegram.zig");
const session_mod = @import("session.zig");
const ConversationContext = @import("agent/prompt.zig").ConversationContext;
const providers = @import("providers/root.zig");
const memory_mod = @import("memory/root.zig");
const bootstrap_mod = @import("bootstrap/root.zig");
const observability = @import("observability.zig");
const tools_mod = @import("tools/root.zig");
const voice = @import("voice.zig");
const health = @import("health.zig");
const daemon = @import("daemon.zig");
const security = @import("security/policy.zig");
const subagent_mod = @import("subagent.zig");
const subagent_runner = @import("subagent_runner.zig");
const agent_routing = @import("agent_routing.zig");
const provider_runtime = @import("providers/runtime_bundle.zig");
const thread_stacks = @import("thread_stacks.zig");
const control_plane = @import("control_plane.zig");
const agent_bindings_config = @import("agent_bindings_config.zig");

const signal = @import("channels/signal.zig");
const matrix = @import("channels/matrix.zig");
const max_mod = @import("channels/max.zig");
const channels_mod = @import("channels/root.zig");
const Atomic = @import("portable_atomic.zig").Atomic;

const log = std.log.scoped(.channel_loop);

/// Set ScheduleTool's default chat_id for delivery context.
            const schedule_tool: *tools_mod.schedule.ScheduleTool = @ptrCast(@alignCast(tool.ptr));

// ════════════════════════════════════════════════════════════════════════════
// Parallel Message Processing
// ════════════════════════════════════════════════════════════════════════════

fn shouldSuppressGroupReply(is_group: bool, reply: []const u8) bool

const TelegramSessionTarget = struct {

const TelegramSessionMapEntry = struct {

const TELEGRAM_BINDING_COMMENT = "Managed by Telegram /bind";

fn currentTelegramSessionTarget(sender: []const u8) TelegramSessionTarget


    const base_chat_id = telegram.targetChatId(sender);

fn currentTelegramBindingKind(is_group: bool) agent_routing.ChatType

fn telegramBindingTargetLabel(is_group: bool, thread_id: ?i64) []const u8

fn matchedByLabel(matched_by: agent_routing.MatchedBy) []const u8

    const base_chat_id = if (is_group) telegram.targetChatId(sender) else sender;
    const thread_id = if (is_group) telegram.targetThreadId(sender) else null;
    const peer_kind = currentTelegramBindingKind(is_group);
    const binding_label = telegramBindingTargetLabel(is_group, thread_id);
    const peer_id = try currentTelegramBindingPeerId(allocator, sender, is_group);

    const exact_binding = agent_bindings_config.findExactPeerBinding(config.agent_bindings, current_target);
    const inherited_binding = agent_bindings_config.findInheritedPeerBinding(config.agent_bindings, current_target);


    var out: std.ArrayList(u8) = .empty;
    const writer = out.writer(allocator);


            var agent_buf: [64]u8 = undefined;
            const agent_id = agent_routing.normalizeId(&agent_buf, agent_profile.name);


    const trimmed = std.mem.trim(u8, arg, " \t\r\n");

    const thread_id = if (is_group) telegram.targetThreadId(sender) else null;
    const binding_label = telegramBindingTargetLabel(is_group, thread_id);
    const peer_id = try currentTelegramBindingPeerId(allocator, sender, is_group);


        const persisted = try agent_bindings_config.persistBindingUpdate(allocator, config.config_path, binding_target, null);
            const live_cfg = @constCast(config);



        const status = try buildTelegramBindingStatusReply(allocator, config, account_id, sender, is_group);

    var agent_buf: [64]u8 = undefined;
    const selected_agent_id = agent_routing.normalizeId(&agent_buf, selected_agent.name);

    const persisted = try agent_bindings_config.persistBindingUpdate(allocator, config.config_path, binding_target, selected_agent.name);
        const live_cfg = @constCast(config);


fn parsePositiveI64(raw: []const u8) ?i64

fn parseTelegramTargetRef(target: []const u8) ?TelegramSessionTarget

fn parseTelegramSessionTargetFromKey(session_key: []const u8) ?TelegramSessionTarget

    const peer_kind: agent_routing.ChatType = if (is_group) .group else .direct;
    var topic_peer_id: ?[]u8 = null;



    const base_key = try std.fmt.allocPrint(allocator, "telegram:{

        var thread_buf: [32]u8 = undefined;
        const thread_key = std.fmt.bufPrint(&thread_buf, "{


    const base_peer_id = if (is_group) telegram.targetChatId(sender) else sender;
    const thread_id = if (is_group) telegram.targetThreadId(sender) else null;


    const canonical_key = try buildThreadedSessionKeyIfNeeded(allocator, canonical_base, thread_id);



    const current_target = currentTelegramSessionTarget(sender);
    const snapshots = try session_mgr.snapshotSessions(allocator);

    var entries: std.ArrayListUnmanaged(TelegramSessionMapEntry) = .empty;

        const target = parseTelegramSessionTargetFromKey(snapshot.session_key) orelse continue;

        fn cmp(_: void, a: TelegramSessionMapEntry, b: TelegramSessionMapEntry) bool

    var out: std.ArrayList(u8) = .empty;
    const writer = out.writer(allocator);
    const now_ts = std.time.timestamp();



        const idle_secs: i64 = @intCast(@max(0, now_ts - entry.last_active));
        const status = if (entry.turn_running) "running" else "idle";
        const is_current = entry.thread_id == current_target.thread_id;



    var greeting_buf: [512]u8 = undefined;
    const name = first_name orelse fallback_name;

    const cmd = control_plane.parseSlashCommand(content) orelse return false;













    const topic_name = std.mem.trim(u8, cmd.arg, " \t\r\n");




    const typing_target = sender;
    const draft_turn_id = tg_ptr.startTypingTurn(typing_target) catch 0;

    // Set ScheduleTool context for delivery.

    // Build conversation context for Telegram

    const sink = tg_ptr.makeSink(&stream_ctx);




/// Task context for processing a message in a worker thread.
const MessageTask = struct {

/// Wrapper for thread spawn compatibility
fn messageTaskWorker(task_ptr: *MessageTask) void

const TELEGRAM_OFFSET_STORE_VERSION: i64 = 1;

fn extractTelegramBotId(bot_token: []const u8) ?[]const u8

fn normalizeTelegramAccountId(allocator: std.mem.Allocator, account_id: []const u8) ![]u8

fn telegramUpdateOffsetPath(allocator: std.mem.Allocator, config: *const Config, account_id: []const u8) ![]u8

/// Load persisted Telegram update offset. Returns null when missing/invalid/stale.
    const path = telegramUpdateOffsetPath(allocator, config, account_id) catch return null;

    const file = std.fs.openFileAbsolute(path, .{

/// Persist Telegram update offset with bot identity (atomic write).
    const path = try telegramUpdateOffsetPath(allocator, config, account_id);


    var buf: std.ArrayList(u8) = .empty;


    const tmp_path = try std.fmt.allocPrint(allocator, "{

/// Persist candidate Telegram offset only when it advanced beyond the last
/// persisted value. On write failure, keeps watermark unchanged so the caller
/// retries on the next loop iteration.

fn signalGroupPeerId(reply_target: ?[]const u8) []const u8

fn matrixRoomPeerId(reply_target: ?[]const u8) []const u8

// ════════════════════════════════════════════════════════════════════════════
// TelegramLoopState — shared state between supervisor and polling thread
// ════════════════════════════════════════════════════════════════════════════

pub const TelegramLoopState = struct {
    /// Updated after each pollUpdates() — epoch seconds.
    /// Supervisor sets this to ask the polling thread to stop.
    /// Thread handle for join().

// Re-export centralized ProviderHolder from providers module.
pub const ProviderHolder = providers.ProviderHolder;

// ════════════════════════════════════════════════════════════════════════════
// ChannelRuntime — container for polling-thread dependencies
// ════════════════════════════════════════════════════════════════════════════

pub const ChannelRuntime = struct {
    /// Initialize the runtime from config — mirrors main.zig:702-786 setup.

// ════════════════════════════════════════════════════════════════════════════
// runTelegramLoop — polling thread function
// ════════════════════════════════════════════════════════════════════════════

/// Thread-entry function for the Telegram polling loop.
/// Mirrors main.zig:793-866 but checks `loop_state.stop_requested` and
/// `daemon.isShutdownRequested()` for graceful shutdown.
///
/// `tg_ptr` is the channel instance owned by the supervisor (ChannelManager).
/// The polling loop uses it directly instead of creating a second
/// TelegramChannel, so health checks and polling operate on the same object.
    // Set up transcription — key comes from providers.{audio_media.provider}
    const trans = config.audio_media;

    // Restore persisted Telegram offset (OpenClaw parity).

    // Ensure polling mode is active without dropping queued updates.

    // Register bot commands
    var persisted_update_id: i64 = tg_ptr.last_update_id;

    var evict_counter: u32 = 0;


    // Update activity timestamp at start

    // Parallel worker bookkeeping.
    // Keep at most one in-flight worker per session_key to preserve order.
    var active_worker_threads: std.StringHashMapUnmanaged(std.Thread) = .empty;
    var active_worker_order: std.ArrayListUnmanaged([]const u8) = .empty;
            const key = active_worker_order.orderedRemove(0);

    const enable_parallel = max_parallel_tasks > 1;


        // Update activity after each poll (even if no messages)

            // Reply-to logic
            const use_reply_to = msg.is_group or tg_ptr.reply_in_private;
            const reply_to_id: ?i64 = if (use_reply_to) msg.message_id else null;




                var handled_in_worker = false;
                        var interrupt = runtime.session_mgr.requestTurnInterrupt(session_key);
                        var dynamic_notice: ?[]u8 = null;

                    // Preserve message order per session_key.
                        var idx: usize = 0;

                    // Bound total parallelism per channel loop instance.
                        const oldest_key = active_worker_order.orderedRemove(0);

                    // Spawn a worker thread for this message.









            // Synchronous processing



        // Periodic session eviction


// ════════════════════════════════════════════════════════════════════════════
// SignalLoopState — shared state between supervisor and polling thread
// ════════════════════════════════════════════════════════════════════════════

pub const SignalLoopState = struct {
    /// Updated after each pollMessages() — epoch seconds.
    /// Supervisor sets this to ask the polling thread to stop.
    /// Thread handle for join().

// ════════════════════════════════════════════════════════════════════════════
// runSignalLoop — polling thread function
// ════════════════════════════════════════════════════════════════════════════

/// Thread-entry function for the Signal SSE polling loop.
/// Mirrors runTelegramLoop but uses signal-cli's SSE/JSON-RPC API.
/// Checks `loop_state.stop_requested` and `daemon.isShutdownRequested()`
/// for graceful shutdown.
    // Update activity timestamp at start

    var evict_counter: u32 = 0;


        // Update activity after each poll (even if no messages)

            const schedule_chat_id = msg.reply_target orelse msg.sender;

            // Session key — always resolve through agent routing (falls back on errors)
            var key_buf: [128]u8 = undefined;
            const group_peer_id = signalGroupPeerId(msg.reply_target);
            var routed_session_key: ?[]const u8 = null;

            const typing_target = msg.reply_target;

            // Build conversation context for Signal


            // Reply on Signal


        // Periodic session eviction


// ════════════════════════════════════════════════════════════════════════════
// MatrixLoopState — shared state between supervisor and polling thread
// ════════════════════════════════════════════════════════════════════════════

pub const MatrixLoopState = struct {
    /// Updated after each pollMessages() — epoch seconds.
    /// Supervisor sets this to ask the polling thread to stop.
    /// Thread handle for join().

// ════════════════════════════════════════════════════════════════════════════
// MaxLoopState — shared state between supervisor and polling thread
// ════════════════════════════════════════════════════════════════════════════

pub const MaxLoopState = struct {
    /// Updated after each pollUpdates() — epoch seconds.
    /// Supervisor sets this to ask the polling thread to stop.
    /// Thread handle for join().


pub const PollingSpawnResult = struct {

    const tg_ls = try allocator.create(TelegramLoopState);

    const tg_ptr: *telegram.TelegramChannel = @ptrCast(@alignCast(channel.ptr));


    const sg_ls = try allocator.create(SignalLoopState);

    const sg_ptr: *signal.SignalChannel = @ptrCast(@alignCast(channel.ptr));


    const mx_ls = try allocator.create(MatrixLoopState);

    const mx_ptr: *matrix.MatrixChannel = @ptrCast(@alignCast(channel.ptr));


// ════════════════════════════════════════════════════════════════════════════
// runMatrixLoop — polling thread function
// ════════════════════════════════════════════════════════════════════════════

/// Thread-entry function for Matrix /sync polling.
/// Uses account-aware route resolution and per-room reply targets.

    var evict_counter: u32 = 0;



            const schedule_chat_id = msg.reply_target orelse msg.sender;

            var key_buf: [192]u8 = undefined;
            const room_peer_id = matrixRoomPeerId(msg.reply_target);
            var routed_session_key: ?[]const u8 = null;



            const typing_target = msg.reply_target orelse msg.sender;






    const mx_ls = try allocator.create(MaxLoopState);

    const mx_ptr: *max_mod.MaxChannel = @ptrCast(@alignCast(channel.ptr));


// ════════════════════════════════════════════════════════════════════════════
// runMaxLoop — polling thread function
// ════════════════════════════════════════════════════════════════════════════

/// Thread-entry function for Max Bot API long-polling.
/// Uses account-aware route resolution and per-chat reply targets.
    // 1. Fetch bot identity


    var evict_counter: u32 = 0;
    var backoff_ns: u64 = std.time.ns_per_s;
    const max_backoff_ns: u64 = 30 * std.time.ns_per_s;


        // Reset backoff on success

            const reply_target = msg.reply_target orelse msg.sender;

            var key_buf: [192]u8 = undefined;
            var routed_session_key: ?[]const u8 = null;

                const peer_id = if (msg.is_group) reply_target else msg.sender;




            const sink = mx_ptr.makeSink(&stream_ctx);







// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "TelegramLoopState init defaults" {
    const state = TelegramLoopState.init();

test "TelegramLoopState stop_requested toggle" {
    var state = TelegramLoopState.init();

test "TelegramLoopState last_activity update" {
    var state = TelegramLoopState.init();
    const before = state.last_activity.load(.acquire);
    const after = state.last_activity.load(.acquire);

test "shouldSuppressGroupReply suppresses only group replies with marker" {

test "isStopLikeCommand matches stop and abort variants" {

test "isStopLikeCommand rejects non-control commands" {

test "ProviderHolder tagged union fields" {
    // Compile-time check that ProviderHolder has expected variants

test "channel runtime wires security policy into session manager and shell tool" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "SignalLoopState init defaults" {
    const state = SignalLoopState.init();

test "SignalLoopState stop_requested toggle" {
    var state = SignalLoopState.init();

test "SignalLoopState last_activity update" {
    var state = SignalLoopState.init();
    const before = state.last_activity.load(.acquire);
    const after = state.last_activity.load(.acquire);

test "MatrixLoopState init defaults" {
    const state = MatrixLoopState.init();

test "MatrixLoopState stop_requested toggle" {
    var state = MatrixLoopState.init();

test "MatrixLoopState last_activity update" {
    var state = MatrixLoopState.init();
    const before = state.last_activity.load(.acquire);
    const after = state.last_activity.load(.acquire);

test "MaxLoopState init defaults" {
    const state = MaxLoopState.init();

test "MaxLoopState stop_requested toggle" {
    var state = MaxLoopState.init();

test "MaxLoopState last_activity update" {
    var state = MaxLoopState.init();
    const before = state.last_activity.load(.acquire);
    const after = state.last_activity.load(.acquire);

test "signalGroupPeerId extracts group id from reply target" {
    const peer_id = signalGroupPeerId("group:1203630@g.us");

test "signalGroupPeerId falls back when reply target is missing or malformed" {

test "matrixRoomPeerId falls back when reply target is missing" {

test "parseTelegramSessionTargetFromKey handles encoded telegram topic peers" {
    const parsed = parseTelegramSessionTargetFromKey("agent:main:telegram:group:-100123#topic:77") orelse return error.TestExpectedEqual;

test "parseTelegramSessionTargetFromKey handles thread suffix session keys" {
    const parsed = parseTelegramSessionTargetFromKey("agent:main:telegram:group:-100123:thread:77") orelse return error.TestExpectedEqual;

test "parseTelegramSessionTargetFromKey handles legacy telegram fallback keys" {
    const parsed = parseTelegramSessionTargetFromKey("telegram:main:-100123#topic:77") orelse return error.TestExpectedEqual;

test "parseTelegramSessionTargetFromKey handles canonical telegram fallback thread keys" {
    const parsed = parseTelegramSessionTargetFromKey("telegram:main:-100123:thread:77") orelse return error.TestExpectedEqual;

test "resolveTelegramBaseRouteKey matches topic-specific telegram binding before group fallback" {
    const allocator = std.testing.allocator;

    const key = try resolveTelegramBaseRouteKey(allocator, &cfg, "main", "-100123", 77, true);


test "resolveTelegramBaseRouteKey falls back to base telegram group binding for unmatched topic" {
    const allocator = std.testing.allocator;

    const key = try resolveTelegramBaseRouteKey(allocator, &cfg, "main", "-100123", 77, true);


test "buildTelegramBindingStatusReply distinguishes exact and inherited peer bindings" {
    const allocator = std.testing.allocator;

    const reply = try buildTelegramBindingStatusReply(allocator, &cfg, "main", "-100123#topic:77", true);


test "telegram update offset store roundtrip" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "telegram update offset store returns null for mismatched bot id" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "telegram update offset store treats legacy payload without bot_id as stale" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{

test "telegram offset persistence helper retries after write failure" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{
