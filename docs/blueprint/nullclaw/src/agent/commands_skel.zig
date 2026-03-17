const std = @import("std");
const builtin = @import("builtin");
const providers = @import("../providers/root.zig");
const Tool = @import("../tools/root.zig").Tool;
const skills_mod = @import("../skills.zig");
const spawn_tool_mod = @import("../tools/spawn.zig");
const subagent_mod = @import("../subagent.zig");
const memory_mod = @import("../memory/root.zig");
const config_types = @import("../config_types.zig");
const config_module = @import("../config.zig");
const capabilities_mod = @import("../capabilities.zig");
const config_mutator = @import("../config_mutator.zig");
const context_tokens = @import("context_tokens.zig");
const max_tokens_resolver = @import("max_tokens.zig");
const control_plane = @import("../control_plane.zig");
const provider_names = @import("../provider_names.zig");
const version = @import("../version.zig");
const command_summary = @import("../command_summary.zig");
const log = std.log.scoped(.agent);

const SlashCommand = control_plane.SlashCommand;
const parseSlashCommand = control_plane.parseSlashCommand;
const isSlashName = control_plane.isSlashName;


pub fn bareSessionResetPrompt(message: []const u8) ?[]const u8

pub const TurnInputPlan = struct {

const SlashCommandKind = enum {

fn classifySlashCommand(cmd: SlashCommand) SlashCommandKind

fn slashCommandClearsSession(kind: SlashCommandKind) bool

pub fn planTurnInput(message: []const u8) TurnInputPlan

pub fn persistedRuntimeCommand(message: []const u8) ?[]const u8

fn firstToken(arg: []const u8) []const u8

fn parsePositiveUsize(raw: []const u8) ?usize

fn isInternalMemoryEntryKeyOrContent(key: []const u8, content: []const u8) bool

fn memoryRuntimePtr(self: anytype) ?*memory_mod.MemoryRuntime

fn setModelName(self: anytype, model: []const u8) !void

fn setDefaultProvider(self: anytype, provider_name: []const u8) !void

fn isConfiguredProviderName(self: anytype, provider_name: []const u8) bool

fn hasExplicitProviderPrefix(self: anytype, model: []const u8) bool

fn configPrimaryModelForSelection(self: anytype, model: []const u8) ![]u8

fn persistSelectedModelToConfig(self: anytype, model: []const u8) !void

fn invalidateSystemPromptCache(self: anytype) void

test "configPrimaryModelForSelection treats unknown leading segment as model for default provider" {
    const allocator = std.testing.allocator;
    var dummy = struct {

    const primary = try configPrimaryModelForSelection(&dummy, "inception/mercury");

test "configPrimaryModelForSelection keeps explicit known provider prefix" {
    const allocator = std.testing.allocator;
    var dummy = struct {

    const primary = try configPrimaryModelForSelection(&dummy, "openrouter/inception/mercury");

test "configPrimaryModelForSelection treats known provider prefix case-insensitively" {
    const allocator = std.testing.allocator;
    var dummy = struct {

    const primary = try configPrimaryModelForSelection(&dummy, "OpenRouter/inception/mercury");

test "configPrimaryModelForSelection keeps explicit configured custom provider prefix" {
    const allocator = std.testing.allocator;
    var dummy = struct {

    const primary = try configPrimaryModelForSelection(&dummy, "customgw/model-a");

test "bareSessionResetPrompt returns prompt for bare /new" {
    const prompt = bareSessionResetPrompt("/new") orelse return error.TestExpectedEqual;

test "bareSessionResetPrompt returns prompt for bare /reset with mention" {
    const prompt = bareSessionResetPrompt("/reset@nullclaw_bot:") orelse return error.TestExpectedEqual;

test "bareSessionResetPrompt ignores /reset with argument" {

test "planTurnInput routes bare reset through local clear and llm prompt" {
    const plan = planTurnInput("/reset@nullclaw_bot:");

test "planTurnInput keeps unknown slash-prefixed text on llm path" {
    const plan = planTurnInput("/etc/hosts");

test "planTurnInput keeps known slash commands local-only" {
    const plan = planTurnInput("/help");

test "planTurnInput keeps /menu on local-only path" {
    const plan = planTurnInput("/menu");

test "hotApplyConfigChange updates model primary as provider plus model" {
    const allocator = std.testing.allocator;
    var dummy = struct {


test "hotApplyConfigChange rejects malformed model primary" {
    const allocator = std.testing.allocator;
    var dummy = struct {


test "hotApplyConfigChange model primary refreshes token and max token limits" {
    const allocator = std.testing.allocator;
    var dummy = struct {


test "hotApplyConfigChange updates agent status_show_emojis" {
    const allocator = std.testing.allocator;
    var dummy = struct {


test "applyHotReloadConfig restores resolved defaults and invalidates prompt cache" {
    const allocator = std.testing.allocator;

    var dummy = struct {


    const summary = try applyHotReloadConfig(&dummy, &cfg);


test "splitPrimaryModelRef parses provider model format" {
    const parsed = splitPrimaryModelRef("openrouter/inception/mercury") orelse return error.TestUnexpectedResult;

test "splitPrimaryModelRef rejects malformed values" {

fn setExecNodeId(self: anytype, value: ?[]const u8) !void

fn setTtsProvider(self: anytype, value: ?[]const u8) !void

fn setFocusTarget(self: anytype, value: ?[]const u8) !void

fn setDockTarget(self: anytype, value: ?[]const u8) !void

fn clearPendingExecCommand(self: anytype) void

fn setPendingExecCommand(self: anytype, command: []const u8) !void

fn splitFirstToken(arg: []const u8) struct

fn isSkillNameSeparator(ch: u8) bool

fn nextSkillNameToken(name: []const u8, index: *usize) ?[]const u8

fn skillNamesEqualNormalized(left: []const u8, right: []const u8) bool


fn findSkillByExactName(skills: []const skills_mod.Skill, name: []const u8) ?*const skills_mod.Skill

fn findSkillByNameNormalized(skills: []const skills_mod.Skill, name: []const u8) SkillLookup

fn formatAmbiguousSkillName(self: anytype, name: []const u8) ![]const u8

const DirectSkillCommandMatch = struct {


fn executeSkillInvocation(self: anytype, skill: *const skills_mod.Skill, user_input: []const u8) ![]const u8

fn tryHandleDirectSkillCommand(self: anytype, cmd: SlashCommand) !?[]const u8

const SUBAGENTS_SPAWN_USAGE = "Usage: /subagents spawn [--agent <name>|--agent=<name>] <task>";

const SubagentSpawnRequest = struct {

fn parseSubagentSpawnRequest(arg: []const u8) ?SubagentSpawnRequest

test "parseSubagentSpawnRequest parses plain task" {
    const parsed = parseSubagentSpawnRequest("run quick check") orelse return error.TestUnexpectedResult;

test "parseSubagentSpawnRequest parses --agent form" {
    const parsed = parseSubagentSpawnRequest("--agent researcher gather references") orelse return error.TestUnexpectedResult;

test "parseSubagentSpawnRequest parses --agent= form" {
    const parsed = parseSubagentSpawnRequest("--agent=researcher gather references") orelse return error.TestUnexpectedResult;

test "parseSubagentSpawnRequest rejects invalid input" {

test "parseSubagentSpawnRequest parses newline-separated agent and task" {
    const parsed = parseSubagentSpawnRequest("--agent researcher\ncheck logs") orelse return error.TestUnexpectedResult;

fn testSubagentRunnerEcho(allocator: std.mem.Allocator, request: subagent_mod.TaskRunRequest) ![]const u8

test "handleSubagentsCommand spawn with named agent reports profile usage" {
    var manager = subagent_mod.SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "handleSubagentsCommand spawn with unknown named agent reports clear error" {
    var manager = subagent_mod.SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "handleSubagentsCommand spawn supports multiline task after --agent" {
    var manager = subagent_mod.SubagentManager.init(std.testing.allocator, &cfg, null, .{

test "handleSubagentsCommand help documents both agent flag forms" {
    var harness = struct {

    const response = try handleSubagentsCommand(&harness, "help");

fn parseTaskId(raw: []const u8) ?u64

fn findSpawnTool(self: anytype) ?*spawn_tool_mod.SpawnTool

fn findSubagentManager(self: anytype) ?*subagent_mod.SubagentManager

pub fn refreshSubagentToolContext(self: anytype) void

fn findShellTool(self: anytype) ?Tool

fn clearSessionState(self: anytype) void

fn formatWhoAmI(self: anytype) ![]const u8

fn parseReasoningEffort(raw: []const u8) ?[]const u8

fn parseVerboseLevel(comptime T: type, raw: []const u8) ?T

fn parseReasoningMode(comptime T: type, raw: []const u8) ?T

fn parseUsageMode(comptime T: type, raw: []const u8) ?T

fn parseExecHost(comptime T: type, raw: []const u8) ?T

fn parseExecSecurity(comptime T: type, raw: []const u8) ?T

fn parseExecAsk(comptime T: type, raw: []const u8) ?T

fn parseQueueMode(comptime T: type, raw: []const u8) ?T

fn parseQueueDrop(comptime T: type, raw: []const u8) ?T

fn parseTtsMode(comptime T: type, raw: []const u8) ?T

fn parseActivationMode(comptime T: type, raw: []const u8) ?T

fn parseSendMode(comptime T: type, raw: []const u8) ?T

fn parseDurationMs(raw: []const u8) ?u32

fn parseDurationSeconds(raw: []const u8) ?u64

fn resetRuntimeCommandState(self: anytype) void

fn formatStatus(self: anytype) ![]const u8

fn handleThinkCommand(self: anytype, arg: []const u8) ![]const u8

fn handleVerboseCommand(self: anytype, arg: []const u8) ![]const u8

fn handleReasoningCommand(self: anytype, arg: []const u8) ![]const u8

fn handleExecCommand(self: anytype, arg: []const u8) ![]const u8

fn handleQueueCommand(self: anytype, arg: []const u8) ![]const u8

fn handleUsageCommand(self: anytype, arg: []const u8) ![]const u8

fn handleTtsCommand(self: anytype, arg: []const u8) ![]const u8

fn handleAllowlistCommand(self: anytype, arg: []const u8) ![]const u8

fn handleContextCommand(self: anytype, arg: []const u8) ![]const u8

fn handleExportSessionCommand(self: anytype, arg: []const u8) ![]const u8

fn handleSessionCommand(self: anytype, arg: []const u8) ![]const u8

fn handleFocusCommand(self: anytype, arg: []const u8) ![]const u8

fn handleUnfocusCommand(self: anytype) ![]const u8

fn handleDockCommand(self: anytype, channel: []const u8) ![]const u8

fn handleActivationCommand(self: anytype, arg: []const u8) ![]const u8

fn handleSendCommand(self: anytype, arg: []const u8) ![]const u8

fn handleElevatedCommand(self: anytype, arg: []const u8) ![]const u8

fn parseApproveDecision(raw: []const u8) ?enum

fn runShellCommand(self: anytype, command: []const u8, skip_approval_gate: bool) ![]const u8

fn handleApproveCommand(self: anytype, arg: []const u8) ![]const u8

fn taskStatusLabel(status: subagent_mod.TaskStatus) []const u8

fn currentSubagentSessionKey(self: anytype) []const u8

fn taskBelongsToCurrentSession(self: anytype, state: *const subagent_mod.TaskState) bool

fn freeSubagentTaskState(manager: *subagent_mod.SubagentManager, state: *subagent_mod.TaskState) void

fn formatSubagentList(self: anytype, include_details: bool) ![]const u8

fn spawnSubagentTask(self: anytype, task: []const u8, label: []const u8, agent_name: ?[]const u8) ![]const u8

fn handleAgentsCommand(self: anytype) ![]const u8

fn handleKillCommand(self: anytype, arg: []const u8) ![]const u8

fn handleSubagentsCommand(self: anytype, arg: []const u8) ![]const u8

fn handleSteerCommand(self: anytype, arg: []const u8) ![]const u8

fn handleTellCommand(self: anytype, arg: []const u8) ![]const u8

fn handlePollCommand(self: anytype) ![]const u8

fn handleStopCommand(self: anytype) ![]const u8

fn parseJsonStringOwned(allocator: std.mem.Allocator, raw: []const u8) !?[]u8

fn parseJsonF64(raw: []const u8) ?f64

fn parseJsonU32(raw: []const u8) ?u32

fn parseJsonU64(raw: []const u8) ?u64

fn parseJsonBool(raw: []const u8) ?bool

fn splitPrimaryModelRef(primary: []const u8) ?struct


const HotReloadSummary = struct {


        const primary = try parseJsonStringOwned(self.allocator, new_value_json) orelse return false;
        const parsed = splitPrimaryModelRef(primary) orelse return false;

        const temp = parseJsonF64(new_value_json) orelse return false;

        const v = parseJsonU32(new_value_json) orelse return false;

        const v = parseJsonU32(new_value_json) orelse return false;

        const v = parseJsonU64(new_value_json) orelse return false;

        const v = parseJsonBool(new_value_json) orelse return false;


fn loadHotReloadConfig(backing_allocator: std.mem.Allocator) !config_module.Config

        const model = cfg.default_model orelse return allocator.dupe(u8, "null");
        const primary = try std.fmt.allocPrint(allocator, "{







fn applyHotReloadConfig(self: anytype, cfg: *const config_module.Config) !HotReloadSummary

    const mode = if (dry_run) "preview" else "applied";
    const restart_text = if (result.requires_restart) "true" else "false";
    const hot_text = if (hot_applied) "true" else "false";
    const backup = result.backup_path orelse "(none)";


fn handleCapabilitiesCommand(self: anytype, arg: []const u8) ![]const u8

fn handleConfigCommand(self: anytype, arg: []const u8) ![]const u8

fn handleSkillCommand(self: anytype, arg: []const u8) ![]const u8

fn handleBashCommand(self: anytype, arg: []const u8) ![]const u8

pub fn isExecToolName(tool_name: []const u8) bool

pub fn execBlockMessage(self: anytype, args: std.json.ObjectMap) ?[]const u8

    const show_reasoning = self.reasoning_mode != .off and reasoning_content != null and reasoning_content.?.len > 0;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    const w = out.writer(self.allocator);




fn handleDoctorCommand(self: anytype) ![]const u8

pub fn handleSlashCommand(self: anytype, message: []const u8) !?[]const u8

fn handleMemoryCommand(self: anytype, arg: []const u8) ![]const u8
