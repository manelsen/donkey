const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const Config = @import("../config.zig").Config;
const NamedAgentConfig = @import("../config.zig").NamedAgentConfig;
const ProviderEntry = @import("../config_types.zig").ProviderEntry;
const provider_names = @import("../provider_names.zig");
const providers = @import("../providers/root.zig");


var test_complete_agent_prompt_override: ?TestCompleteFn = null;

/// Delegate tool — delegates a subtask to a named sub-agent with a different
/// provider/model configuration. Supports depth enforcement to prevent
/// infinite delegation chains.
pub const DelegateTool = struct {
    /// Named agent configs from the global config (lookup by name).
    /// Provider entries from config for API key/base URL/runtime option lookup.
    /// Fallback API key if agent-specific key is not set.
    /// Current delegation depth. Incremented for sub-delegates.

// ── Tests ───────────────────────────────────────────────────────────
var test_expected_provider_name: ?[]const u8 = null;
var test_expected_api_key: ?[]const u8 = null;
var test_expected_base_url: ?[]const u8 = null;
var test_expected_native_tools: ?bool = null;
var test_expected_user_agent: ?[]const u8 = null;
var test_expected_model_name: ?[]const u8 = null;
var test_expected_system_prompt: ?[]const u8 = null;
var test_expected_prompt: ?[]const u8 = null;


test "delegate tool name" {
    var dt = DelegateTool{

test "delegate schema has agent and prompt" {
    var dt = DelegateTool{

test "delegate executes gracefully without config" {
    var dt = DelegateTool{

test "delegate missing agent" {
    var dt = DelegateTool{

test "delegate missing prompt" {
    var dt = DelegateTool{

test "delegate blank agent rejected" {
    var dt = DelegateTool{

test "delegate blank prompt rejected" {
    var dt = DelegateTool{

test "delegate with valid params handles missing provider gracefully" {
    var dt = DelegateTool{

test "delegate schema has context field" {
    var dt = DelegateTool{

test "delegate schema has required array" {
    var dt = DelegateTool{

test "delegate empty JSON rejected" {
    var dt = DelegateTool{

test "delegate with context field handles missing provider gracefully" {
    var dt = DelegateTool{

// ── Depth enforcement tests ─────────────────────────────────────

test "delegate depth limit enforced" {
    const t = dt.tool();
    const parsed = try root.parseTestArgs("{

test "delegate depth within limit proceeds" {
    const t = dt.tool();
    // Will proceed past depth check but fail at provider level (no API key)
    const parsed = try root.parseTestArgs("{

test "delegate default depth limit at 3" {
    const t = dt.tool();
    const parsed = try root.parseTestArgs("{

test "delegate per-agent max_depth" {
    const t = dt.tool();

    // "shallow" at depth=1 should be blocked (max_depth=1)
    const p1 = try root.parseTestArgs("{

test "delegate agents config stored" {

test "delegate uses parsed agent model.primary provider ref" {
    const allocator = std.testing.allocator;




    var dt = DelegateTool{

test "delegate uses configured provider entry for key and base_url" {
    const allocator = std.testing.allocator;


    const tool = dt.tool();
    const parsed = try root.parseTestArgs("{
