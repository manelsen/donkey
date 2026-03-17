const std = @import("std");
const platform = @import("platform.zig");
const provider_names = @import("provider_names.zig");
pub const config_types = @import("config_types.zig");
pub const config_parse = @import("config_parse.zig");
/// Write a JSON-escaped string (with enclosing quotes) to any writer.
/// Mirrors json_util.appendJsonString but works with writer-based output.
fn writeJsonStr(w: anytype, s: []const u8) !void

// ── Re-export all types so downstream `@import("config.zig").Foo` still works ──

pub const AutonomyLevel = config_types.AutonomyLevel;
pub const HardwareTransport = config_types.HardwareTransport;
pub const SandboxBackend = config_types.SandboxBackend;
pub const DiagnosticsConfig = config_types.DiagnosticsConfig;
pub const AutonomyConfig = config_types.AutonomyConfig;
pub const DockerRuntimeConfig = config_types.DockerRuntimeConfig;
pub const RuntimeConfig = config_types.RuntimeConfig;
pub const ModelFallbackEntry = config_types.ModelFallbackEntry;
pub const ReliabilityConfig = config_types.ReliabilityConfig;
pub const SchedulerConfig = config_types.SchedulerConfig;
pub const AgentConfig = config_types.AgentConfig;
pub const ToolFilterGroup = config_types.ToolFilterGroup;
pub const ToolFilterGroupMode = config_types.ToolFilterGroupMode;
pub const ModelRouteConfig = config_types.ModelRouteConfig;
pub const HeartbeatConfig = config_types.HeartbeatConfig;
pub const CronConfig = config_types.CronConfig;
pub const TelegramConfig = config_types.TelegramConfig;
pub const DiscordConfig = config_types.DiscordConfig;
pub const SlackReceiveMode = config_types.SlackReceiveMode;
pub const SlackConfig = config_types.SlackConfig;
pub const WebhookConfig = config_types.WebhookConfig;
pub const IMessageConfig = config_types.IMessageConfig;
pub const MatrixConfig = config_types.MatrixConfig;
pub const MaxConfig = config_types.MaxConfig;
pub const MattermostConfig = config_types.MattermostConfig;
pub const WhatsAppConfig = config_types.WhatsAppConfig;
pub const IrcConfig = config_types.IrcConfig;
pub const LarkReceiveMode = config_types.LarkReceiveMode;
pub const LarkConfig = config_types.LarkConfig;
pub const DingTalkConfig = config_types.DingTalkConfig;
pub const SignalConfig = config_types.SignalConfig;
pub const EmailConfig = config_types.EmailConfig;
pub const LineConfig = config_types.LineConfig;
pub const QQGroupPolicy = config_types.QQGroupPolicy;
pub const QQReceiveMode = config_types.QQReceiveMode;
pub const QQConfig = config_types.QQConfig;
pub const OneBotConfig = config_types.OneBotConfig;
pub const MaixCamConfig = config_types.MaixCamConfig;
pub const WebConfig = config_types.WebConfig;
pub const ChannelsConfig = config_types.ChannelsConfig;
pub const MemoryConfig = config_types.MemoryConfig;
pub const TunnelConfig = config_types.TunnelConfig;
pub const GatewayConfig = config_types.GatewayConfig;
pub const A2aConfig = config_types.A2aConfig;
pub const ComposioConfig = config_types.ComposioConfig;
pub const SecretsConfig = config_types.SecretsConfig;
pub const BrowserComputerUseConfig = config_types.BrowserComputerUseConfig;
pub const BrowserConfig = config_types.BrowserConfig;
pub const HttpRequestConfig = config_types.HttpRequestConfig;
pub const IdentityConfig = config_types.IdentityConfig;
pub const CostConfig = config_types.CostConfig;
pub const PeripheralBoardConfig = config_types.PeripheralBoardConfig;
pub const PeripheralsConfig = config_types.PeripheralsConfig;
pub const HardwareConfig = config_types.HardwareConfig;
pub const SandboxConfig = config_types.SandboxConfig;
pub const ResourceLimitsConfig = config_types.ResourceLimitsConfig;
pub const AuditConfig = config_types.AuditConfig;
pub const SecurityConfig = config_types.SecurityConfig;
pub const DelegateAgentConfig = config_types.DelegateAgentConfig;
pub const NamedAgentConfig = config_types.NamedAgentConfig;
pub const McpServerConfig = config_types.McpServerConfig;
pub const ModelPricing = config_types.ModelPricing;
pub const ToolsConfig = config_types.ToolsConfig;
pub const ProviderEntry = config_types.ProviderEntry;
pub const AudioMediaConfig = config_types.AudioMediaConfig;
pub const DmScope = config_types.DmScope;
pub const IdentityLink = config_types.IdentityLink;
pub const SessionConfig = config_types.SessionConfig;
pub const NostrConfig = config_types.NostrConfig;

const SerializedNamedAgentConfig = struct {

fn freeNamedAgentSlice(allocator: std.mem.Allocator, agents: []const NamedAgentConfig) void

// ── Top-level Config ────────────────────────────────────────────

pub const Config = struct {
    // Computed paths (not serialized)
    // Top-level fields
    // Model routing and delegate agents
    /// Runtime-only flag used by live `/bind` updates.
    // Nested sub-configs
    // Convenience aliases for backward-compat flat access used by other modules.
    // These are set during load() to mirror nested values.
    /// Look up a provider's API key from the providers list.

    fn writeNostrChannel(w: *std.Io.Writer, ns: NostrConfig) !void

    fn writeStringArray(w: *std.Io.Writer, values: []const []const u8) !void

    fn writeReliabilitySection(self: *const Config, w: *std.Io.Writer) !void

    fn writeMcpServersSection(self: *const Config, w: *std.Io.Writer) !void

    /// Apply NULLCLAW_* environment variable overrides.
    pub fn applyEnvOverrides(self: *Config) void

    /// Save config as JSON to the config_path.
    pub fn save(self: *const Config) !void

    // ── Validation ──────────────────────────────────────────────


    pub fn validate(self: *const Config) ValidationError!void

    /// Print a human-readable validation error to stderr.
    pub fn printValidationError(err: ValidationError) void

    /// Print configured models summary to stderr (for startup banners).
    pub fn printModelConfig(self: *const Config) void

// ── Tests ───────────────────────────────────────────────────────

/// Helper used by tests to compare paths on Windows without worrying about
/// JSON escaping or backslashes vs. forward slashes. Converts all '\\' to '/'.
fn normalizePathSeparators(allocator: std.mem.Allocator, path: []const u8) ![]const u8

test "json parse roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();






test "validation rejects bad temperature" {

test "json parse reads reliability fallback providers and model fallbacks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();




test "validation rejects zero port" {

test "validation passes for defaults" {

test "validation rejects plaintext secrets" {

test "validation rejects null default_model" {

test "validation rejects top-level default_provider" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    var cfg = Config{

test "json parse top-level default_model" {
    const allocator = std.testing.allocator;
    var cfg = Config{

test "validation rejects top-level default_model even when nested model exists" {
    const allocator = std.testing.allocator;
    // use an arena to match production behavior (both allocs are freed together)
    var arena = std.heap.ArenaAllocator.init(allocator);
    const a = arena.allocator();
    var cfg = Config{

test "validation rejects defaults.model.primary without provider prefix" {
    const allocator = std.testing.allocator;
    var cfg = Config{

test "save includes channels section by default" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{