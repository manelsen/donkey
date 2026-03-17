//! Agent Routing — agent bindings routing system.
//!
//! Routes incoming messages to the correct agent based on a tiered matching
//! system. Bindings are checked against the input in priority order:
//!   1. peer        — exact peer (kind + id) match
//!   2. parent_peer — peer matches the parent (e.g. thread starter)
//!   3. guild_roles — guild_id + at least one matching role
//!   4. guild       — guild_id only (no roles)
//!   5. team        — team_id match
//!   6. account     — channel + account_id only
//!   7. channel_only— channel only (no account_id/peer/guild/team/roles)
//!
//! If no binding matches, the default agent is used (first in agents list,
//! or "main" if the list is empty).

const std = @import("std");
const config_types = @import("config_types.zig");
const NamedAgentConfig = config_types.NamedAgentConfig;

// ═══════════════════════════════════════════════════════════════════════════
// Types
// ═══════════════════════════════════════════════════════════════════════════

pub const ChatType = enum {

pub const PeerRef = struct {

pub const BindingMatch = struct {

pub const AgentBinding = struct {

pub const MatchedBy = enum {

pub const ResolvedRoute = struct {

pub const RouteInput = struct {

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Normalize an ID: lowercase, replace non-alphanumeric with '-',
/// strip leading/trailing dashes, cap at 64 chars.
/// Returns "default" for empty or all-dash input.
pub fn normalizeId(buf: *[64]u8, input: []const u8) []const u8

/// Resolve a peer ID through identity links. If the peer matches any
/// link's peers list, return the canonical name instead.

/// Build a DM-scope-aware session key.
/// Returns owned slice; caller must free with the same allocator.

/// Build a session key respecting DmScope and identity links.
    var norm_buf: [64]u8 = undefined;
    const norm_agent = normalizeId(&norm_buf, agent_id);


        // Groups and channels always use per-channel-peer scope

        // Resolve identity links for DM peers
        const resolved_peer = resolveLinkedPeerId(p.id, identity_links);


/// Build the main session key for an agent: `agent:{id}:main`.
pub fn buildMainSessionKey(allocator: std.mem.Allocator, agent_id: []const u8) ![]u8

/// Append `:thread:{threadId}` to a base session key.
pub fn buildThreadSessionKey(allocator: std.mem.Allocator, base_key: []const u8, thread_id: []const u8) ![]u8

/// Strip `:thread:{threadId}` suffix to get the parent session key.
/// Returns null if the key doesn't contain a thread suffix.
pub fn resolveThreadParentSessionKey(key: []const u8) ?[]const u8

/// Find the default agent from a named agents list.
/// Returns the first agent's name, or "main" if the list is empty.
pub fn findDefaultAgent(agents: []const NamedAgentConfig) []const u8

/// Check if two PeerRef values match (same kind and id).
pub fn peerMatches(binding_peer: ?PeerRef, input_peer: ?PeerRef) bool

/// Pre-filter: check that a binding's channel and account_id constraints
/// match the input. A null constraint means "any" (matches everything).
pub fn bindingMatchesScope(binding: AgentBinding, input: RouteInput) bool

/// Returns true if the binding has no peer, guild_id, team_id, or roles set
/// (only channel and/or account_id).
fn isAccountOnly(b: AgentBinding) bool

/// Returns true if the binding has only a channel constraint (no account_id,
/// peer, guild_id, team_id, or roles).
fn isChannelOnly(b: AgentBinding) bool

/// Check ALL constraints on a binding against input. Each constraint on the
/// binding must match the corresponding input field. Null constraints match
/// anything (they impose no restriction).
fn allConstraintsMatch(b: AgentBinding, input: RouteInput, check_peer: ?PeerRef) bool

/// Check if any role in `binding_roles` appears in `member_roles`.
fn hasMatchingRole(binding_roles: []const []const u8, member_roles: []const []const u8) bool

    // Within the same routing tier, prefer bindings scoped to the current
    // account before broader unscoped fallbacks.




// ═══════════════════════════════════════════════════════════════════════════
// Route resolution
// ═══════════════════════════════════════════════════════════════════════════

/// Resolve the agent route for a given input.
///
/// Walks 7 tiers of binding matches in priority order and returns the
/// first match found. Falls back to the default agent if none match.
/// The returned `session_key` is allocated; caller must free it.
    // Pre-filter bindings by channel + account_id scope.
    var candidates: std.ArrayListUnmanaged(AgentBinding) = .empty;


    // Tier 1: peer match — binding has a peer constraint that matches input.peer

    // Tier 2: parent_peer match — binding peer matches input.parent_peer

    // Tier 3: guild_id + roles match

    // Tier 4: guild_id only (no roles on binding)

    // Tier 5: team_id match

    // Tier 6: account only (channel + account_id, no peer/guild/team/roles)

    // Tier 7: channel only (no account_id/peer/guild/team/roles)

    // No match — use default agent.
    const default_id = findDefaultAgent(agents);

/// Resolve a route and build session keys using configured session scope settings.
/// Applies dm_scope and identity_links to the returned session_key.
    var route = try resolveRoute(allocator, input, bindings, agents);


/// Internal helper to construct a ResolvedRoute with allocated session keys.
    const session_key = try buildSessionKey(allocator, agent_id, input.channel, input.peer);
    const main_key = try buildMainSessionKey(allocator, agent_id);

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

test {

test "resolveRoute — no bindings returns default agent" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &.{

test "resolveRoute — peer match returns correct agent" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — guild+roles match (tier 3)" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — guild-only match (tier 4)" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — channel-only match (tier 7)" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — tier priority: peer wins over guild" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — parent_peer match (tier 2)" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — team match (tier 5)" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — account match (tier 6)" {
    const allocator = std.testing.allocator;
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — scope pre-filter excludes mismatched channel" {
    const allocator = std.testing.allocator;
    // Input is on "telegram", not "discord" — binding should be excluded.
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "resolveRoute — guild_roles no matching role falls to guild tier" {
    const allocator = std.testing.allocator;
    // User has "member" role, not "admin" — role binding should NOT match,
    // but guild-only binding should.
    const route = try resolveRoute(allocator, input, &bindings, &.{

test "buildSessionKey — with peer" {
    const allocator = std.testing.allocator;


test "buildSessionKey — without peer" {
    const allocator = std.testing.allocator;
    const key = try buildSessionKey(allocator, "bot1", "telegram", null);


test "buildSessionKey — group peer kind" {
    const allocator = std.testing.allocator;


test "buildSessionKey — channel peer kind" {
    const allocator = std.testing.allocator;


test "findDefaultAgent — empty list returns main" {
    const result = findDefaultAgent(&.{

test "findDefaultAgent — returns first agent name" {
    const result = findDefaultAgent(&agents);

test "peerMatches — both present and equal" {

test "peerMatches — different kind" {

test "peerMatches — different id" {

test "peerMatches — binding null" {

test "peerMatches — input null" {

test "peerMatches — both null" {

test "bindingMatchesScope — null constraints match anything" {
    const b = AgentBinding{

test "bindingMatchesScope — matching channel and account" {
    const input = RouteInput{

test "bindingMatchesScope — mismatched channel" {
    const input = RouteInput{

test "bindingMatchesScope — mismatched account_id" {
    const input = RouteInput{

test "bindingMatchesScope — channel matches, account null (any)" {
    const input = RouteInput{

// ═══════════════════════════════════════════════════════════════════════════
// Phase 2 tests: normalizeId, identity links, DM scope, thread keys
// ═══════════════════════════════════════════════════════════════════════════

test "normalizeId — basic lowercase" {
    var buf: [64]u8 = undefined;

test "normalizeId — special chars become dashes" {
    var buf: [64]u8 = undefined;

test "normalizeId — empty returns default" {
    var buf: [64]u8 = undefined;

test "normalizeId — all-dash returns default" {
    var buf: [64]u8 = undefined;

test "normalizeId — strips leading/trailing dashes" {
    var buf: [64]u8 = undefined;

test "resolveLinkedPeerId — no links returns original" {

test "resolveLinkedPeerId — matched link returns canonical" {

test "resolveLinkedPeerId — unmatched returns original" {

test "buildSessionKeyWithScope — per_channel_peer (default)" {
    const allocator = std.testing.allocator;

test "buildSessionKeyWithScope — main scope" {
    const allocator = std.testing.allocator;

test "buildSessionKeyWithScope — per_peer scope" {
    const allocator = std.testing.allocator;

test "buildSessionKeyWithScope — per_account_channel_peer scope" {
    const allocator = std.testing.allocator;

test "buildSessionKeyWithScope — group always per-channel" {
    const allocator = std.testing.allocator;

test "buildSessionKeyWithScope — identity link resolves peer" {
    const allocator = std.testing.allocator;

test "buildMainSessionKey" {
    const allocator = std.testing.allocator;
    const key = try buildMainSessionKey(allocator, "My Bot");

test "buildThreadSessionKey" {
    const allocator = std.testing.allocator;
    const key = try buildThreadSessionKey(allocator, "agent:bot1:discord:direct:user42", "thread99");

test "resolveThreadParentSessionKey — has thread suffix" {
    const parent = resolveThreadParentSessionKey("agent:bot1:discord:direct:user42:thread:t99");

test "resolveThreadParentSessionKey — no thread suffix" {
    const parent = resolveThreadParentSessionKey("agent:bot1:discord:direct:user42");

test "resolveRoute — main_session_key is always set" {
    const allocator = std.testing.allocator;
    const input = RouteInput{

// ═══════════════════════════════════════════════════════════════════════════
// Parity tests: route resolution, session keys, multi-account, normalization
// ═══════════════════════════════════════════════════════════════════════════

test "resolveRoute — defaults to main/default when no bindings" {
    const allocator = std.testing.allocator;

test "resolveRoute — peer binding wins over account binding" {
    const allocator = std.testing.allocator;

test "resolveRoute — account scoped peer binding beats unscoped peer fallback regardless of order" {
    const allocator = std.testing.allocator;



test "resolveRoute — missing accountId in binding matches only that account" {
    const allocator = std.testing.allocator;
    // default account: matches

    // different account: no match, falls to default

test "resolveRoute — defaultAgentId used when no binding matches" {
    const allocator = std.testing.allocator;

test "resolveRoute — peer+guild binding requires guild match" {
    const allocator = std.testing.allocator;
    // guild matches: peer wins

    // guild mismatch: no match

test "resolveRoute — guild binding wins over account when peer not bound" {
    const allocator = std.testing.allocator;

test "resolveRoute — peer binding still beats guild+roles" {
    const allocator = std.testing.allocator;

test "resolveRoute — no member_role_ids means guild+roles doesn't match" {
    const allocator = std.testing.allocator;
        // no member_role_ids

test "resolveRoute — empty roles treated as no role restriction (guild tier)" {
    const allocator = std.testing.allocator;
    // Empty roles = guild-only binding (tier 4), not guild+roles (tier 3)

test "resolveRoute — first matching binding wins with multiple role bindings" {
    const allocator = std.testing.allocator;

test "resolveRoute — parent_peer binding wins over guild binding" {
    const allocator = std.testing.allocator;

// ── dmScope session key tests ───────────────────────────────────────────

test "dmScope controls direct-message session key isolation" {
    const allocator = std.testing.allocator;

test "per_account_channel_peer isolates per account, channel, sender" {
    const allocator = std.testing.allocator;

test "per_account_channel_peer uses default when account not provided" {
    const allocator = std.testing.allocator;

test "identityLinks applies to per_peer scope" {
    const allocator = std.testing.allocator;

test "identityLinks applies to per_channel_peer scope" {
    const allocator = std.testing.allocator;

// ── Session key continuity (DM vs group produce distinct keys) ──────────

test "distinct keys for DM vs channel — main scope" {
    const allocator = std.testing.allocator;

test "distinct keys for DM vs channel — per_peer scope" {
    const allocator = std.testing.allocator;

// ── normalizeId parity tests ────────────────────────────────────────────

test "normalizeId — defaults missing/empty values to default" {
    var buf: [64]u8 = undefined;

test "normalizeId — normalizes valid ids to lowercase" {
    var buf: [64]u8 = undefined;

test "normalizeId — sanitizes invalid characters" {
    var buf: [64]u8 = undefined;

test "normalizeId — truncates at 64 chars" {
    var buf: [64]u8 = undefined;
    const long_input = "a" ** 100;
    const result = normalizeId(&buf, long_input);

// ── Thread session key parity tests ─────────────────────────────────────

test "buildThreadSessionKey — topic suffix for telegram groups" {
    const allocator = std.testing.allocator;
    const base = "agent:main:telegram:group:1";
    const key = try buildThreadSessionKey(allocator, base, "55");

test "resolveThreadParentSessionKey — parses thread suffix" {
    const parent = resolveThreadParentSessionKey("agent:main:slack:channel:C1:thread:123.456");

test "resolveThreadParentSessionKey — DM without thread returns null" {
    const parent = resolveThreadParentSessionKey("agent:main:telegram:direct:user-1");

// ── buildMainSessionKey normalizes agent id ─────────────────────────────

test "buildMainSessionKey — normalizes agent id" {
    const allocator = std.testing.allocator;
    const key = try buildMainSessionKey(allocator, "  Research Bot  ");

test "buildMainSessionKey — empty agent id defaults to main" {
    const allocator = std.testing.allocator;
    const key = try buildMainSessionKey(allocator, "");

// ── resolveLinkedPeerId parity ──────────────────────────────────────────

test "resolveLinkedPeerId — multiple links, first match wins" {

test "resolveLinkedPeerId — empty links returns original" {
