//! Agent core — struct definition, turn loop, tool execution.
//!
//! Sub-modules: dispatcher.zig (tool call parsing), compaction.zig (history
//! compaction/trimming), cli.zig (CLI entry point + REPL), prompt.zig
//! (system prompt), memory_loader.zig (memory enrichment).

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.agent);
const Config = @import("../config.zig").Config;
const config_types = @import("../config_types.zig");
const providers = @import("../providers/root.zig");
const Provider = providers.Provider;
const ChatMessage = providers.ChatMessage;
const ChatResponse = providers.ChatResponse;
const ToolSpec = providers.ToolSpec;
const tools_mod = @import("../tools/root.zig");
const Tool = tools_mod.Tool;
const memory_mod = @import("../memory/root.zig");
const Memory = memory_mod.Memory;
const bootstrap_mod = @import("../bootstrap/root.zig");
const capabilities_mod = @import("../capabilities.zig");
const multimodal = @import("../multimodal.zig");
const platform = @import("../platform.zig");
const observability = @import("../observability.zig");
const Observer = observability.Observer;
const ObserverEvent = observability.ObserverEvent;
const SecurityPolicy = @import("../security/policy.zig").SecurityPolicy;
const verbose_mod = @import("../verbose.zig");

const cache = memory_mod.cache;
pub const dispatcher = @import("dispatcher.zig");
pub const compaction = @import("compaction.zig");
pub const context_tokens = @import("context_tokens.zig");
pub const max_tokens_resolver = @import("max_tokens.zig");
pub const prompt = @import("prompt.zig");
pub const memory_loader = @import("memory_loader.zig");
pub const commands = @import("commands.zig");
const ParsedToolCall = dispatcher.ParsedToolCall;
const ToolExecutionResult = dispatcher.ToolExecutionResult;

// ═══════════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum agentic tool-use iterations per user message.
const DEFAULT_MAX_TOOL_ITERATIONS: u32 = 25;

/// Maximum non-system messages before trimming.
const DEFAULT_MAX_HISTORY: u32 = 50;

pub fn estimate_text_tokens(text: []const u8) u32

// ═══════════════════════════════════════════════════════════════════════════
// Agent
// ═══════════════════════════════════════════════════════════════════════════

pub const Agent = struct {

pub const cli = @import("cli.zig");

/// CLI entry point — re-exported for backward compatibility.
pub const run = cli.run;

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

test "Agent.OwnedMessage toChatMessage" {
    const chat = msg.toChatMessage();

test "Agent trim history preserves system prompt" {
    const allocator = std.testing.allocator;

    // Create a minimal agent config

    var noop = observability.NoopObserver{

test "Agent clear history" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "dispatcher module reexport" {

test "compaction module reexport" {

test "cli module reexport" {

test "prompt module reexport" {

test "memory_loader module reexport" {

test {

// ── Additional agent tests ──────────────────────────────────────

test "Agent.OwnedMessage system role" {
    const chat = msg.toChatMessage();

test "Agent.OwnedMessage assistant role" {
    const chat = msg.toChatMessage();

test "Agent initial state" {
    const allocator = std.testing.allocator;
    var noop = observability.NoopObserver{

test "Agent tokens tracking" {
    const allocator = std.testing.allocator;
    var noop = observability.NoopObserver{

test "Agent trimHistory no-op when under limit" {
    const allocator = std.testing.allocator;
    var noop = observability.NoopObserver{

test "Agent trimHistory without system prompt" {
    const allocator = std.testing.allocator;
    var noop = observability.NoopObserver{

test "Agent clearHistory resets all state" {
    const allocator = std.testing.allocator;
    var noop = observability.NoopObserver{

test "Agent buildMessageSlice" {
    const allocator = std.testing.allocator;
    var noop = observability.NoopObserver{

test "Agent buildProviderMessages uses model-aware vision capability" {
    const DummyProvider = struct {

    var dummy: u8 = 0;
    const prov = Provider{

test "Agent buildProviderMessages allows workspace image paths" {
    const DummyProvider = struct {

    var tmp_dir = std.testing.tmpDir(.{

test "Agent max_tool_iterations default" {

test "Agent max_history default" {

test "Agent trimHistory keeps most recent messages" {
    const allocator = std.testing.allocator;
    var noop = observability.NoopObserver{

test "Agent clearHistory then add messages" {
    const allocator = std.testing.allocator;
    var noop = observability.NoopObserver{

// ── Slash Command Tests ──────────────────────────────────────────

fn makeTestAgent(allocator: std.mem.Allocator) !Agent

fn find_tool_by_name(tools: []const Tool, name: []const u8) ?Tool

test "Agent.fromConfig resolves token limit from model lookup when unset" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent.fromConfig keeps explicit token_limit override" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent.fromConfigWithProfile applies named profile defaults" {
    const allocator = std.testing.allocator;


    var noop = observability.NoopObserver{

test "turn prepends profile system prompt when profile is active" {
    const CaptureProvider = struct {

    const allocator = std.testing.allocator;
    var provider_state = CaptureProvider{

test "Agent.fromConfig resolves max_tokens from provider lookup when unset" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent.fromConfig resolves conservative limits for legacy gpt-4" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent effective max_tokens reserves prompt headroom" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent effective max_tokens does not double count plain content with content_parts" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent effective max_tokens scales with image_base64 size" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent effective max_tokens accounts for native tool schema overhead" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent effective max_tokens can estimate using filtered tool schemas" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent.fromConfig keeps explicit max_tokens override" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent.fromConfig clamps max_tokens to token_limit" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "Agent.fromConfig applies status_show_emojis flag" {
    const allocator = std.testing.allocator;

    var noop = observability.NoopObserver{

test "slash /new clears history" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    // Add some history

    const response = (try agent.handleSlashCommand("/new")).?;


test "slash /reset clears history and switches model" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);


    const response = (try agent.handleSlashCommand("/reset gpt-4o-mini")).?;


test "turn bare /new routes through fresh-session prompt" {
    const EchoProvider = struct {

    const allocator = std.testing.allocator;

    var provider_state = EchoProvider{

test "turn /reset with argument stays slash-only command" {
    const NoCallProvider = struct {

    const allocator = std.testing.allocator;

    var provider_state: u8 = 0;

    var noop = observability.NoopObserver{

test "turn retains user message on provider error" {
    const FailProvider = struct {

    const allocator = std.testing.allocator;

    const provider = Provider{

test "turn does not retry immediately on rate limit" {
    const RateLimitedProvider = struct {

    const allocator = std.testing.allocator;

    var state = RateLimitedProvider.State{

test "turn still retries non-rate-limited provider failures once" {
    const RetryProvider = struct {

    const allocator = std.testing.allocator;

    var state = RetryProvider.State{

test "slash /help returns help text" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/help")).?;


test "slash /commands aliases to help" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/commands")).?;


test "slash /status returns agent info" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/status")).?;


test "slash /status can render without emojis" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/status")).?;


test "slash /whoami returns current session id" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/whoami")).?;


test "slash /model switches model" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model gpt-4o")).?;


test "slash /model with colon switches model" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model: gpt-4.1-mini")).?;


test "slash /model with telegram bot mention switches model" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model@nullclaw_bot qianfan/custom-model")).?;


test "slash /model resolves provider max_tokens fallback" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model qianfan/custom-model")).?;


test "slash /model keeps explicit token_limit override" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model claude-opus-4-6")).?;


test "auto route selects provider-prefixed model ref for fast prompt" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const routed = (try agent.routeModelNameForTurn(allocator, "show current status")).?;


test "auto route selects fast model for short structured prompt" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);



test "auto route keeps ambiguous short prompt on balanced model" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const routed = (try agent.routeModelNameForTurn(allocator, "What should we do here?")).?;


test "auto route selects deep model for investigation prompt" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);



test "auto route records last route trace for short structured prompt" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);



test "model status reports last auto-route trace" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);


    const status = try agent.formatModelStatus();


test "auto route skips degraded fast route after rate limit" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const selection = agent.routeSelectionForTurn("show current status").?;

    const routed = (try agent.routeModelNameForTurn(allocator, "show current status")).?;


    const status = try agent.formatModelStatus();

test "auto route degrades route on out-of-credits provider detail" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);


    const selection = agent.routeSelectionForTurn("show current status").?;

    const routed = (try agent.routeModelNameForTurn(allocator, "show current status")).?;


test "auto route is disabled when model is pinned" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);


test "auto route selection benchmark stays below visible overhead" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const iterations: usize = 50_000;
    var timer = try std.time.Timer.start();
    var i: usize = 0;
        const hint = agent.selectRouteHintForTurn("show current status");
    const elapsed_ns = timer.read();
    const avg_ns = elapsed_ns / iterations;

    // Heuristic routing should stay far below human-visible latency.

test "slash /model auto clears pin and invalidates cached prompt model" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model auto")).?;


test "slash /model auto without routes restores default model and explains routing is not configured" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model auto")).?;


test "slash /model pins explicit selection" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model gpt-4o")).?;


test "slash /model without name shows current" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model ")).?;


test "slash /models aliases to /model" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/models list")).?;


test "slash /model list aliases to model status" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/model list")).?;


test "slash /memory list hides internal autosave and hygiene entries by default" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    var sqlite_mem = try memory_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();



    const response = (try agent.handleSlashCommand("/memory list --limit 10")).?;

test "slash /memory list includes internal entries when requested" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    var sqlite_mem = try memory_mod.SqliteMemory.init(allocator, ":memory:");
    const mem = sqlite_mem.memory();



    const response = (try agent.handleSlashCommand("/memory list --limit 10 --include-internal")).?;

test "slash /model shows provider and model fallback chains" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);



    const response = (try agent.handleSlashCommand("/model")).?;


test "slash /compact with short history is a no-op" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/compact")).?;


test "slash /think updates reasoning effort" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const alias_resp = (try agent.handleSlashCommand("/think on")).?;

    const set_resp = (try agent.handleSlashCommand("/think high")).?;

    const off_resp = (try agent.handleSlashCommand("/think off")).?;

test "slash /verbose updates verbose level" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/verbose full")).?;


test "slash /reasoning updates reasoning mode" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/reasoning stream")).?;


test "slash /exec updates runtime exec settings" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/exec host=sandbox security=full ask=off node=node-1")).?;


test "slash /queue updates queue settings" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/queue debounce debounce:2s cap:25 drop:newest")).?;


test "slash /usage updates usage mode" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/usage full")).?;


test "slash /tts updates tts settings" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/tts always provider openai limit 1200 summary on audio off")).?;


test "slash /stop handled explicitly" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/stop")).?;


test "slash /abort aliases /stop" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("/abort")).?;


test "turn returns interruption reply when interrupt requested" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = try agent.turn("hello");


test "interruption reply lists effectively interrupted tools" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);


    const response = try agent.turn("hello");


test "hard stop mock interruption lists exactly interrupted tool" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    const ProbeTool = struct {

    const OneShotToolProvider = struct {

    const InterruptCtx = struct {
    const InterruptWorker = struct {

    const allocator = std.testing.allocator;
    var started = std.atomic.Value(bool).init(false);
    var tool_impl = ProbeTool{

test "slash /approve executes pending bash command" {
    const allocator = std.testing.allocator;

    const shell_impl = try allocator.create(tools_mod.shell.ShellTool);
    const shell_tool = shell_impl.tool();

    var noop = observability.NoopObserver{

test "slash /restart clears runtime command settings" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const think_resp = (try agent.handleSlashCommand("/think high")).?;
    const verbose_resp = (try agent.handleSlashCommand("/verbose full")).?;
    const usage_resp = (try agent.handleSlashCommand("/usage full")).?;
    const tts_resp = (try agent.handleSlashCommand("/tts always provider test-provider")).?;

    const response = (try agent.handleSlashCommand("/restart")).?;


test "turn includes reasoning and usage footer when enabled" {
    const ProviderState = struct {

    var state: u8 = 0;
    const provider = Provider{

test "turn estimates token usage when provider omits usage" {
    const ProviderState = struct {

    var state: u8 = 0;
    const provider = Provider{

test "turn refreshes system prompt after workspace markdown change" {
    const ReloadProvider = struct {

    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "turn refreshes system prompt after TOOLS.md change" {
    const ReloadProvider = struct {

    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "turn refreshes system prompt after USER.md change" {
    const ReloadProvider = struct {

    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "turn refreshes system prompt when conversation sender changes" {
    const ReloadProvider = struct {

    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "exec security deny blocks shell tool execution" {
    const allocator = std.testing.allocator;
    const shell_impl = try allocator.create(tools_mod.shell.ShellTool);
    const shell_tool = shell_impl.tool();

    var noop = observability.NoopObserver{

test "exec ask always registers pending approval from tool path" {
    const allocator = std.testing.allocator;
    const shell_impl = try allocator.create(tools_mod.shell.ShellTool);
    const shell_tool = shell_impl.tool();

    var noop = observability.NoopObserver{

test "slash additional commands are handled" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);


        const response_opt = try agent.handleSlashCommand(cmd);
        const response = response_opt.?;

test "non-slash message returns null" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = try agent.handleSlashCommand("hello world");

test "slash command with whitespace" {
    const allocator = std.testing.allocator;
    var agent = try makeTestAgent(allocator);

    const response = (try agent.handleSlashCommand("  /help  ")).?;


test "direct slash skill command resolves hyphenated skill name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "direct slash skill command resolves two-word alias to hyphenated skill" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "direct slash skill command does not collapse token boundaries" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "direct slash skill command reports ambiguous normalized alias" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "direct slash skill command does not shadow built in doctor" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "direct slash skill command reports ambiguity between exact and composite matches" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "slash /skill reload invalidates prompt caches" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{