//! Session Manager — persistent in-process Agent sessions.
//!
//! Replaces subprocess spawning with reusable Agent instances keyed by
//! session_key (e.g. "telegram:chat123"). Each session maintains its own
//! conversation history across turns.
//!
//! Thread safety: SessionManager.mutex guards the sessions map (short hold),
//! Session.mutex serializes turn() per session (may be long). Different
//! sessions are processed in parallel.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Config = @import("config.zig").Config;
const fs_compat = @import("fs_compat.zig");
const agent_routing = @import("agent_routing.zig");
const agent_mod = @import("agent/root.zig");
const Agent = agent_mod.Agent;
const ConversationContext = @import("agent/prompt.zig").ConversationContext;
const config_types = @import("config_types.zig");
const providers = @import("providers/root.zig");
const Provider = providers.Provider;
const memory_mod = @import("memory/root.zig");
const Memory = memory_mod.Memory;
const observability = @import("observability.zig");
const Observer = observability.Observer;
const tools_mod = @import("tools/root.zig");
const Tool = tools_mod.Tool;
const SecurityPolicy = @import("security/policy.zig").SecurityPolicy;
const streaming = @import("streaming.zig");
const thread_stacks = @import("thread_stacks.zig");
const log = std.log.scoped(.session);
const MESSAGE_LOG_MAX_BYTES: usize = 4096;
const TOKEN_USAGE_LEDGER_FILENAME = "llm_token_usage.jsonl";
const NS_PER_SEC: i128 = std.time.ns_per_s;
const RUNTIME_COMMAND_ROLE = memory_mod.RUNTIME_COMMAND_ROLE;

fn messageLogPreview(text: []const u8) struct

fn estimateRestoredSessionTokens(entries: []const memory_mod.MessageEntry) u64

fn persistedAssistantReply(agent: *const Agent, response: []const u8) []const u8

fn restorePersistedSessionState(session: *Session, entries: []const memory_mod.MessageEntry) void

fn sessionAgentId(session_key: []const u8) ?[]const u8

fn findProfileForSessionKey(config: *const Config, session_key: []const u8) ?config_types.NamedAgentConfig

const SessionProviderContext = struct {

// ═══════════════════════════════════════════════════════════════════════════
// Session
// ═══════════════════════════════════════════════════════════════════════════

pub const Session = struct {

// ═══════════════════════════════════════════════════════════════════════════
// SessionManager
// ═══════════════════════════════════════════════════════════════════════════

pub const SessionManager = struct {

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

const testing = std.testing;

// ---------------------------------------------------------------------------
// MockProvider — returns a fixed response, no network calls
// ---------------------------------------------------------------------------

const MockProvider = struct {

const MockStreamingProvider = struct {

const DeltaCollector = struct {

const ProbeTool = struct {

const SummaryFailureProvider = struct {

/// Create a test SessionManager with mock provider.
fn testSessionManager(allocator: Allocator, mock: *MockProvider, cfg: *const Config) SessionManager

fn testSessionManagerWithMemory(allocator: Allocator, mock: *MockProvider, cfg: *const Config, mem: ?Memory, session_store: ?memory_mod.SessionStore) SessionManager

fn testConfig() Config

// ---------------------------------------------------------------------------
// 1. Struct tests
// ---------------------------------------------------------------------------

test "SessionManager init/deinit — no leaks" {
    var mock = MockProvider{

test "usage ledger appends records when retention limits are disabled" {
    var tmp = std.testing.tmpDir(.{

test "usage ledger resets when max line limit is reached" {
    var tmp = std.testing.tmpDir(.{

test "usage ledger resets when window expires" {
    var tmp = std.testing.tmpDir(.{

test "usage ledger resets when byte limit would be exceeded" {
    var tmp = std.testing.tmpDir(.{

test "usage ledger records failed response flag" {
    var tmp = std.testing.tmpDir(.{

test "getOrCreate creates new session for unknown key" {
    var mock = MockProvider{

test "getOrCreate returns same session for same key" {
    var mock = MockProvider{

test "getOrCreate creates separate sessions for different keys" {
    var mock = MockProvider{

test "getOrCreate applies named agent profile from routed session key" {
    var mock = MockProvider{

test "getOrCreate stores named agent provider interface from session-owned holder" {
    var mock = MockProvider{

test "getOrCreate falls back to default config for unknown routed agent id" {
    var mock = MockProvider{

test "sessionCount reflects active sessions" {
    var mock = MockProvider{

test "snapshotSessions captures live session metadata" {
    var mock = MockProvider{

test "migrateLegacySessionKey renames in-memory session to canonical key" {
    var mock = MockProvider{

test "migrateLegacySessionKey copies persisted transcript and usage to canonical key" {
    var mock = MockProvider{

test "migrateLegacySessionKey reattaches session-scoped memory to canonical key" {
    var mock = MockProvider{

test "session has correct initial state" {
    var mock = MockProvider{

test "requestTurnInterrupt signals only active sessions" {
    var mock = MockProvider{

test "requestTurnInterrupt returns active tool snapshot when available" {
    var mock = MockProvider{

// ---------------------------------------------------------------------------
// 2. processMessage tests
// ---------------------------------------------------------------------------

test "processMessage returns mock response" {
    var mock = MockProvider{

test "processMessageStreaming forwards provider deltas" {
    var mock = MockStreamingProvider{

test "processMessage refreshes system prompt when conversation context is cleared" {
    var mock = MockProvider{

test "processMessage updates last_active" {
    var mock = MockProvider{

test "processMessage increments turn_count" {
    var mock = MockProvider{

test "processMessage preserves session across calls" {
    var mock = MockProvider{

test "restored session reconstructs token count from persisted assistant replies" {
    var mock = MockProvider{

test "restored session token reconstruction ignores usage footer decorations" {
    var mock = MockProvider{

test "persisted session falls back to rendered response when degraded turn has no final assistant history entry" {
    var provider = SummaryFailureProvider{

test "restored session token reconstruction stays aligned across response cache hits" {
    var mock = MockProvider{

fn expectResetTurnPersistsFreshSession(command: []const u8) !void

test "processMessage bare /new persists fresh-session turn across reload" {

test "processMessage bare /reset with mention persists fresh-session turn across reload" {

test "processMessage slash-prefixed prompt that is not a local command persists across reload" {
    var mock = MockProvider{

test "processMessage runtime slash commands persist across reload" {
    var mock = MockProvider{

test "processMessage different keys — independent sessions" {
    var mock = MockProvider{

test "processMessage /new clears autosave only for current session" {
    var mock = MockProvider{

test "processMessage /new with model clears autosave only for current session" {
    var mock = MockProvider{

test "processMessage /reset clears autosave only for current session" {
    var mock = MockProvider{

test "processMessage /restart clears autosave only for current session" {
    var mock = MockProvider{

test "processMessage with sqlite memory first turn does not panic" {
    var mock = MockProvider{

// ---------------------------------------------------------------------------
// 3. evictIdle tests
// ---------------------------------------------------------------------------

test "evictIdle removes old sessions" {
    var mock = MockProvider{

test "evictIdle preserves recent sessions" {
    var mock = MockProvider{

test "evictIdle returns correct count" {
    var mock = MockProvider{

test "evictIdle with no sessions returns 0" {
    var mock = MockProvider{

test "evictIdle preserves sessions with active turns" {
    var mock = MockProvider{

// ---------------------------------------------------------------------------
// 4. Thread safety tests
// ---------------------------------------------------------------------------

test "concurrent getOrCreate same key — single Session created" {
    var mock = MockProvider{

test "concurrent getOrCreate different keys — separate Sessions" {
    var mock = MockProvider{

test "concurrent processMessage different keys — no crash" {
    var mock = MockProvider{

test "concurrent processMessage with sqlite memory does not panic" {
    var mock = MockProvider{

// ---------------------------------------------------------------------------
// 5. Session consolidation tests
// ---------------------------------------------------------------------------

test "session last_consolidated defaults to zero" {
    var mock = MockProvider{

test "session initial state includes last_consolidated" {
    var mock = MockProvider{

// ---------------------------------------------------------------------------
// 6. reloadSkillsAll tests
// ---------------------------------------------------------------------------

test "reloadSkillsAll with no sessions returns zero counts" {
    var mock = MockProvider{

test "reloadSkillsAll invalidates system prompt on all sessions" {
    var mock = MockProvider{

test "reloadSkillsAll does not affect session count" {
    var mock = MockProvider{
