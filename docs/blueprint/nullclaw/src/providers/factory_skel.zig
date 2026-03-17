const std = @import("std");
const root = @import("root.zig");
const Provider = root.Provider;
const anthropic = @import("anthropic.zig");
const openai = @import("openai.zig");
const ollama = @import("ollama.zig");
const gemini = @import("gemini.zig");
const vertex = @import("vertex.zig");
const openrouter = @import("openrouter.zig");
const compatible = @import("compatible.zig");
const claude_cli = @import("claude_cli.zig");
const codex_cli = @import("codex_cli.zig");
const openai_codex = @import("openai_codex.zig");
const provider_names = @import("../provider_names.zig");

pub const ProviderKind = enum {

// ════════════════════════════════════════════════════════════════════════════
// Single source of truth for all OpenAI-compatible providers.
// To add a new provider, add ONE entry here.
// ════════════════════════════════════════════════════════════════════════════

const CompatProvider = struct {
    /// When true, disable the /v1/responses fallback on 404.
    /// When true, merge system messages into first user message.
    /// Authentication style (default: Bearer token).
    /// Whether this provider supports native OpenAI-style tool_calls.
    /// When set, cap max_tokens in non-streaming requests to this value.
    /// Fireworks rejects max_tokens > 4096 when stream=false.
    /// When true, include `"thinking":{"type":"enabled"}` in request bodies
    /// when reasoning_effort is set. Required by Z.AI/GLM thinking models.
    /// When true, include `"enable_thinking":true` in request bodies
    /// when reasoning_effort is set. Required by Qwen (DashScope compatible mode).
    /// When true, include `"reasoning_split":true` in request bodies
    /// when reasoning_effort is set. Used by MiniMax to separate reasoning output.

    // ── Major Cloud Providers ─────────────────────────────────────────────

    // ── Gateways & Aggregators ────────────────────────────────────────────

    // ── China Providers — general ─────────────────────────────────────────

    // ── China Providers — CN endpoints ────────────────────────────────────

    // ── International variants ────────────────────────────────────────────

    // ── Coding-specific endpoints ─────────────────────────────────────────

    // ── Infrastructure & Cloud ────────────────────────────────────────────

    // ── Local Servers ─────────────────────────────────────────────────────

// Comptime check: no duplicate names in the compat_providers table.
comptime {

/// Look up a compatible provider entry by name.
fn findCompatProvider(name: []const u8) ?CompatProvider

const AZURE_DEFAULT_BASE_URL = "https://your-resource.openai.azure.com";
const AZURE_DEFAULT_COMPAT_BASE_URL = "https://your-resource.openai.azure.com/openai/v1";

fn trimTrailingSlash(s: []const u8) []const u8

fn normalizeAzureBaseUrlOwned(allocator: std.mem.Allocator, base_url: ?[]const u8) ![]u8

/// Core (non-compatible) providers that have their own dedicated implementations.

/// Determine which provider to create from a name string.
pub fn classifyProvider(name: []const u8) ProviderKind

/// Auto-detect provider kind from an API key prefix.
pub fn detectProviderByApiKey(key: []const u8) ProviderKind

/// Get the base URL for an OpenAI-compatible provider by name.
pub fn compatibleProviderUrl(name: []const u8) ?[]const u8

/// Get the display name for an OpenAI-compatible provider.
pub fn compatibleProviderDisplayName(name: []const u8) []const u8

/// Tagged union so the concrete provider struct lives alongside the caller
/// (stack or heap) and its vtable pointer remains stable.

    /// Obtain the vtable-based Provider interface from whichever variant is active.
    pub fn provider(self: *ProviderHolder) Provider

    /// Release any resources owned by the active provider variant.
    pub fn deinit(self: *ProviderHolder) void

    /// Create a ProviderHolder from a provider name string and optional API key.
    /// Uses `classifyProvider` to route to the correct concrete provider.
        const kind = classifyProvider(provider_name);
                const azure_url = normalizeAzureBaseUrlOwned(allocator, base_url) catch null;
                var prov = ollama.OllamaProvider.init(allocator, base_url);
                // Config base_url overrides built-in URL table and custom: prefix

                const cp = findCompatProvider(provider_name);


                // Apply flags from the compat_providers table.

                // Apply config-level native_tools override (can only force to false).

            // Unknown provider: if base_url is configured, treat as OpenAI-compatible;
            // otherwise fall back to OpenRouter.

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "classifyProvider identifies known providers" {

test "classifyProvider new providers" {

test "compatibleProviderUrl returns correct URLs" {

test "compatibleProviderUrl fixed URLs" {
    // These 5 URLs were corrected from the original values.

test "compatibleProviderUrl new providers" {

test "normalizeAzureBaseUrlOwned appends openai v1 path" {
    const alloc = std.testing.allocator;

    const plain = try normalizeAzureBaseUrlOwned(alloc, "https://resource.openai.azure.com");

    const openai_only = try normalizeAzureBaseUrlOwned(alloc, "https://resource.openai.azure.com/openai/");

    const v1 = try normalizeAzureBaseUrlOwned(alloc, "https://resource.openai.azure.com/openai/v1/");

test "normalizeAzureBaseUrlOwned strips terminal responses endpoint" {
    const alloc = std.testing.allocator;

    const responses = try normalizeAzureBaseUrlOwned(alloc, "https://resource.openai.azure.com/openai/v1/responses/");

test "compatibleProviderUrl CN/intl variants" {

test "nvidia resolves to correct URL" {

test "lm-studio resolves to localhost:1234" {

test "astrai resolves to astrai API URL" {

test "anthropic-custom prefix classifies as anthropic provider" {

test "new providers display names" {

test "new providers classify as compatible" {

test "findCompatProvider returns correct flags" {
    // GLM has no_responses_fallback and thinking_param
    const glm = findCompatProvider("glm").?;

    // MiniMax has both flags
    const minimax = findCompatProvider("minimax").?;

    // Qwen requires enable_thinking in compatible mode.
    const qwen = findCompatProvider("qwen").?;

    // Groq has no special flags
    const groq_p = findCompatProvider("groq").?;

    // minimax-cn also has both flags
    const minimax_cn = findCompatProvider("minimax-cn").?;

    // Fireworks has non-streaming max_tokens cap.
    const fireworks = findCompatProvider("fireworks").?;

test "fromConfig applies no_responses_fallback flag" {
    const alloc = std.testing.allocator;
    var h = ProviderHolder.fromConfig(alloc, "glm", "key", null, true, null);

test "fromConfig applies thinking_param flag for GLM" {
    const alloc = std.testing.allocator;
    var h = ProviderHolder.fromConfig(alloc, "glm", "key", null, true, null);

test "fromConfig thinking_param false for non-GLM providers" {
    const alloc = std.testing.allocator;
    var h = ProviderHolder.fromConfig(alloc, "groq", "key", null, true, null);

test "fromConfig applies enable_thinking_param for Qwen" {
    const alloc = std.testing.allocator;
    var h = ProviderHolder.fromConfig(alloc, "qwen", "key", null, true, null);

test "fromConfig applies reasoning_split_param for MiniMax" {
    const alloc = std.testing.allocator;
    var h = ProviderHolder.fromConfig(alloc, "minimax", "key", null, true, null);

test "fromConfig applies merge_system_into_user flag" {
    const alloc = std.testing.allocator;
    var h = ProviderHolder.fromConfig(alloc, "minimax", "key", null, true, null);

test "fromConfig inherits native_tools=false from table" {
    const alloc = std.testing.allocator;
    // minimax has native_tools = false in table
    var h = ProviderHolder.fromConfig(alloc, "minimax", "key", null, true, null);

test "fromConfig applies native_tools override for ollama" {
    const alloc = std.testing.allocator;
    var h = ProviderHolder.fromConfig(alloc, "ollama", null, null, false, null);

test "fromConfig applies max_tokens_non_streaming from table" {
    const alloc = std.testing.allocator;
    var h = ProviderHolder.fromConfig(alloc, "fireworks", "key", null, true, null);

test "detectProviderByApiKey openrouter" {

test "detectProviderByApiKey anthropic" {

test "detectProviderByApiKey openai" {

test "detectProviderByApiKey groq" {

test "detectProviderByApiKey xai" {

test "detectProviderByApiKey perplexity" {

test "detectProviderByApiKey aws" {

test "detectProviderByApiKey gemini" {

test "detectProviderByApiKey vertex oauth token" {

test "detectProviderByApiKey unknown" {

test "detectProviderByApiKey short key" {

test "ProviderHolder tagged union has all expected fields" {

test "ProviderHolder.fromConfig routes to correct variant" {
    const alloc = std.testing.allocator;
    // anthropic
    var h1 = ProviderHolder.fromConfig(alloc, "anthropic", "sk-test", null, true, null);
    // openai
    var h2 = ProviderHolder.fromConfig(alloc, "openai", "sk-test", null, true, null);
    // azure openai
    var h2a = ProviderHolder.fromConfig(alloc, "azure", "test-key", "https://test.openai.azure.com", true, null);
    // gemini
    var h3 = ProviderHolder.fromConfig(alloc, "gemini", "key", null, true, null);
    // vertex
    var h3b = ProviderHolder.fromConfig(alloc, "vertex", "ya29.token", "https://aiplatform.googleapis.com/v1/projects/p/locations/global/publishers/google/models", true, null);
    // ollama
    var h4 = ProviderHolder.fromConfig(alloc, "ollama", null, null, true, null);
    // openrouter
    var h5 = ProviderHolder.fromConfig(alloc, "openrouter", "sk-or-test", null, true, null);
    // compatible (groq)
    var h6 = ProviderHolder.fromConfig(alloc, "groq", "gsk_test", null, true, null);
    // compatible (telnyx from built-in table URL)
    var h6b = ProviderHolder.fromConfig(alloc, "telnyx", "test-key", null, true, null);
    // openai-codex
    var h7 = ProviderHolder.fromConfig(alloc, "openai-codex", null, null, true, null);
    // unknown falls back to openrouter
    var h8 = ProviderHolder.fromConfig(alloc, "nonexistent", "key", null, true, null);
    // anthropic-custom prefix
    var h9 = ProviderHolder.fromConfig(alloc, "anthropic-custom:https://my-api.example.com", "sk-test", null, true, null);

test "compat_providers table count" {
    // Verify we have the expected number of entries (guard against accidental deletions).
