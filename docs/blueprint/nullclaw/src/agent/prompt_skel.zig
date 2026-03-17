const std = @import("std");
const builtin = @import("builtin");
const fs_compat = @import("../fs_compat.zig");
const platform = @import("../platform.zig");
const memory_root = @import("../memory/root.zig");
const tools_mod = @import("../tools/root.zig");
const path_prefix = @import("../path_prefix.zig");
const Tool = tools_mod.Tool;
const skills_mod = @import("../skills.zig");
const bootstrap_mod = @import("../bootstrap/root.zig");
const BootstrapProvider = bootstrap_mod.BootstrapProvider;
const pathStartsWith = path_prefix.pathStartsWith;

// ═══════════════════════════════════════════════════════════════════════════
// System Prompt Builder
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum characters to include from a single workspace identity file.
const BOOTSTRAP_MAX_CHARS: usize = 20_000;
/// Read one extra byte via providers so prompt rendering can distinguish
/// "exactly at cap" from "truncated beyond cap" without loading full files.
const BOOTSTRAP_PROVIDER_EXCERPT_BYTES: usize = BOOTSTRAP_MAX_CHARS + 1;
/// Maximum total characters from injected bootstrap identity files.
const BOOTSTRAP_TOTAL_MAX_CHARS: usize = 24_000;
/// Maximum bytes allowed for guarded workspace bootstrap file reads.
const MAX_WORKSPACE_BOOTSTRAP_FILE_BYTES: u64 = 2 * 1024 * 1024;

const GuardedWorkspaceFileOpen = struct {

fn deinitGuardedWorkspaceFile(allocator: std.mem.Allocator, opened: GuardedWorkspaceFileOpen) void

/// Best-effort device id for fingerprint parity with OpenClaw's
/// dev+ino+size+mtime identity tuple.
fn workspaceFileDeviceId(file: *const std.fs.File) ?u64

fn isWorkspaceBootstrapFilenameSafe(filename: []const u8) bool


    const workspace_root = std.fs.cwd().realpathAlloc(allocator, workspace_dir) catch return null;

    const candidate = std.fs.path.join(allocator, &.{

/// Conversation context for the current turn.
/// Carries per-message sender metadata so the LLM always knows who is talking.
pub const ConversationContext = struct {
    // Signal
    // Discord
    // Shared
    /// Compute a hash fingerprint of sender-identifying fields so the system
    /// prompt can be rebuilt when the *sender* changes, not just when context
    /// goes from null ↔ non-null.

/// Context passed to prompt sections during construction.
pub const PromptContext = struct {

/// Build a lightweight fingerprint for workspace prompt files.
/// Used to detect when AGENTS/SOUL/etc changed and system prompt must be rebuilt.
    // When a bootstrap provider is available, delegate fingerprinting to it.

    // Fallback: file-based fingerprinting.
    var hasher = std.hash.Fnv1a_64.init();


        const opened = openWorkspaceFileWithGuards(allocator, workspace_dir, filename);

        const guarded = opened.?;

        const stat = guarded.stat;


        const inode_id = stat.inode;
        const mtime_ns: i128 = stat.mtime;
        const size_bytes: u64 = @intCast(stat.size);


/// Build the full system prompt from workspace identity files, tools, and runtime context.
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = buf.writer(allocator);

    // Identity section — inject workspace MD files

    // Attachment marker conventions for channel delivery.

    // Conversation context section (Signal-specific for now)
        // Show sender identity: "Sender: Name (UUID)" or just "Sender: (UUID)"
        // Discord sender fields


    // Safety section

    // Group chat behavior section (Telegram-only for now).
    // The [NO_REPLY] marker is currently suppressed only by the Telegram loop.
        const is_telegram = if (cc.channel) |ch| std.ascii.eqlIgnoreCase(ch, "telegram") else false;

            // Add schedule tool guidance for Telegram group chats.

    // Schedule tool guidance for all contexts (including private chats)

    // Skills section

    // Workspace section

    // DateTime section

    // Runtime section

    // Tool use protocol and available tools


    var remaining_bootstrap_chars: usize = BOOTSTRAP_TOTAL_MAX_CHARS;
    var hit_total_bootstrap_limit = false;




    // Inject MEMORY.md if present, otherwise fallback to memory.md.


test "buildSystemPrompt includes SOUL persona guidance" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt includes AGENTS operational guidance" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt includes TOOLS availability guidance" {
    const allocator = std.testing.allocator;


test "buildSystemPrompt blocks AGENTS symlink escape outside workspace" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    var ws_tmp = std.testing.tmpDir(.{

fn appendChannelAttachmentsSection(w: anytype) !void

fn writeToolInstructionsSection(w: anytype, tools: anytype) !void

/// Allocating wrapper around writeToolInstructionsSection for callers
/// that need the tool instructions as a standalone string (e.g. subagent runner).
pub fn buildToolInstructions(allocator: std.mem.Allocator, tools: anytype) ![]const u8

fn writeXmlEscapedAttrValue(w: anytype, value: []const u8) !void

/// Append available skills with progressive loading.
/// - always=true skills: full instruction text in the prompt
/// - always=false skills: XML summary only (agent must use file_read to load)
/// - unavailable skills: marked with available="false" and missing deps
    // Two-source loading: workspace skills + ~/.nullclaw/skills/
    const home_dir = platform.getHomeDir(allocator) catch null;

    // listSkillsMerged already calls checkRequirements on each skill.
    // The fallback listSkills path needs explicit checkRequirements calls.
    var used_merged = false;

    // checkRequirements only needed for the non-merged path


    var has_active = false;
    var has_available = false;




            const skill_path = if (skill.path.len > 0) skill.path else workspace_dir;

/// Append a human-readable UTC date/time section derived from the system clock.
fn appendDateTimeSection(w: anytype) !void

/// Read a workspace file and append it to the prompt, truncating if too large.
    // Try bootstrap provider first when available.
        const content = bp.load_excerpt(allocator, filename, BOOTSTRAP_PROVIDER_EXCERPT_BYTES) catch null;
        // Provider returned null — fall through to file-based path.

    // Fallback: direct file read.
    const opened = openWorkspaceFileWithGuards(allocator, workspace_dir, filename);
    var guarded = opened.?;


    // The caller already size-guards workspace bootstrap files to 2 MiB max.
    // Read the guarded file and let appendPromptSectionContent enforce
    // per-file and total prompt truncation semantics consistently.


    const trimmed = std.mem.trim(u8, content, " \t\r\n");


    const total_limited_len = @min(file_limited.len, remaining_bootstrap_chars.*);
    const total_limited = file_limited[0..total_limited_len];


    const truncated_by_file = trimmed.len > BOOTSTRAP_MAX_CHARS;
    const truncated_by_total = total_limited_len < file_limited.len;


    // When bootstrap provider is available, try loading MEMORY.md through it.
        const memory_files = [_][]const u8{

    // Fallback: direct file-based injection.
    var seen_memory_paths: std.StringHashMapUnmanaged(void) = .empty;
        var it = seen_memory_paths.keyIterator();

    const memory_files = [_][]const u8{

    const opened = openWorkspaceFileWithGuards(allocator, workspace_dir, filename);

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

test "pathStartsWith handles root prefixes" {

test "buildToolInstructions includes protocol and tool metadata" {
    const allocator = std.testing.allocator;
    const MockTool = struct {
    const tools = [_]MockTool{

test "buildSystemPrompt includes core sections" {
    const allocator = std.testing.allocator;


test "buildSystemPrompt includes prompt injection hardening guidance" {
    const allocator = std.testing.allocator;


test "buildSystemPrompt emits a single tool listing section" {
    const allocator = std.testing.allocator;
    const MockPromptTool = struct {
    var mock_tool = MockPromptTool{

test "buildSystemPrompt includes workspace dir" {
    const allocator = std.testing.allocator;


test "buildSystemPrompt includes channel attachment marker guidance" {
    const allocator = std.testing.allocator;


test "buildSystemPrompt omits telegram-only group marker guidance for non-telegram groups" {
    const allocator = std.testing.allocator;


test "buildSystemPrompt includes telegram group marker guidance for telegram groups" {
    const allocator = std.testing.allocator;


test "buildSystemPrompt includes discord sender identity fields" {
    const allocator = std.testing.allocator;


test "buildSystemPrompt injects memory.md when MEMORY.md is absent" {
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt injects BOOTSTRAP.md when present" {
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt reads bootstrap docs from sqlite provider when workspace files are absent" {
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt project context stays equivalent across markdown hybrid and sqlite backends" {
    const backends = [_][]const u8{

test "buildSystemPrompt injects HEARTBEAT.md when present" {
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt injects IDENTITY.md when present" {
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt injects USER.md when present" {
    var tmp = std.testing.tmpDir(.{

test "appendPromptSectionContent skips section when total budget is exhausted" {
    const allocator = std.testing.allocator;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = buf.writer(allocator);

    var remaining_bootstrap_chars: usize = 0;
    var hit_total_bootstrap_limit = false;


test "buildSystemPrompt truncates project context at total bootstrap budget" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt omits per-file truncation marker when total budget stops earlier" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt truncates oversized disk bootstrap files instead of failing read" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint is stable when files are unchanged" {
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint changes when tracked file changes" {
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint changes when MEMORY.md changes" {
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint changes when memory.md changes" {
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint changes when BOOTSTRAP.md changes" {
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint changes when HEARTBEAT.md changes" {
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint changes when IDENTITY.md changes" {
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint changes when AGENTS.md changes" {
    var tmp = std.testing.tmpDir(.{

test "workspacePromptFingerprint changes when USER.md changes" {
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt includes both MEMORY.md and memory.md when distinct" {
    var tmp = std.testing.tmpDir(.{

test "appendDateTimeSection outputs UTC timestamp" {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = buf.writer(std.testing.allocator);

    const output = buf.items;
    // Verify the year is plausible (2025+)

test "appendSkillsSection with no skills produces nothing" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const w = buf.writer(allocator);


test "appendSkillsSection renders summary XML for always=false skill" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "appendSkillsSection escapes XML attributes in summary output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "appendSkillsSection supports markdown-only installed skill" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "appendSkillsSection renders full instructions for always=true skill" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "appendSkillsSection renders mixed always=true and always=false" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "appendSkillsSection renders unavailable skill with missing deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "appendSkillsSection unavailable always=true skill renders in XML not full" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "installSkill end-to-end appears in buildSystemPrompt" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "buildSystemPrompt datetime appears before runtime" {
    const allocator = std.testing.allocator;

    const dt_pos = std.mem.indexOf(u8, prompt, "## Current Date & Time") orelse return error.SectionNotFound;
    const rt_pos = std.mem.indexOf(u8, prompt, "## Runtime") orelse return error.SectionNotFound;
