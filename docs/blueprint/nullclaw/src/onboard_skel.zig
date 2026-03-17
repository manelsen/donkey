//! Onboarding — interactive setup wizard and quick setup for nullclaw.
//!
//! Mirrors ZeroClaw's onboard module:
//!   - Interactive wizard (9-step configuration flow)
//!   - Quick setup (non-interactive, sensible defaults)
//!   - Workspace scaffolding (prompt context files + bootstrap lifecycle)
//!   - Channel configuration
//!   - Memory backend selection
//!   - Provider/model selection with curated defaults

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const fs_compat = @import("fs_compat.zig");
const platform = @import("platform.zig");
const codex_support = @import("codex_support.zig");
const config_mod = @import("config.zig");
const Config = config_mod.Config;
const channel_catalog = @import("channel_catalog.zig");
const provider_names = @import("provider_names.zig");
const memory_root = @import("memory/root.zig");
const http_util = @import("http_util.zig");
const json_util = @import("json_util.zig");
const util = @import("util.zig");
const bootstrap_mod = @import("bootstrap/root.zig");

// ── Constants ────────────────────────────────────────────────────


const WORKSPACE_STATE_DIR = ".nullclaw";
const WORKSPACE_STATE_FILE = "workspace-state.json";
const WORKSPACE_STATE_VERSION: i64 = 1;

const WorkspaceOnboardingState = struct {

const WORKSPACE_AGENTS_TEMPLATE = @embedFile("workspace_templates/AGENTS.md");
const WORKSPACE_SOUL_TEMPLATE = @embedFile("workspace_templates/SOUL.md");
const WORKSPACE_TOOLS_TEMPLATE = @embedFile("workspace_templates/TOOLS.md");
const WORKSPACE_IDENTITY_TEMPLATE = @embedFile("workspace_templates/IDENTITY.md");
const WORKSPACE_USER_TEMPLATE = @embedFile("workspace_templates/USER.md");
const WORKSPACE_HEARTBEAT_TEMPLATE = @embedFile("workspace_templates/HEARTBEAT.md");
const WORKSPACE_BOOTSTRAP_TEMPLATE = @embedFile("workspace_templates/BOOTSTRAP.md");
// ── Project context ──────────────────────────────────────────────

pub const ProjectContext = struct {

// ── Provider helpers ─────────────────────────────────────────────

pub const ProviderInfo = struct {

    // --- Tier 1: Major multi-provider gateways ---

    // --- Tier 2: Major cloud providers (Feb 2026 models) ---

    // --- Tier 3: OpenAI-compatible specialists ---

    // --- Tier 4: AI platform specialists ---

    // --- Tier 5: Cloud gateways ---

    // --- Tier 6: Infrastructure providers ---

    // --- Tier 7: Enterprise clouds ---

    // --- Tier 8: Emerging platforms ---

    // --- Tier 9: Local/self-hosted ---

    // --- Tier 10: CLI-based providers ---

/// Canonicalize provider name (handle aliases).
pub fn canonicalProviderName(name: []const u8) []const u8

fn findProviderInfoByCanonical(name: []const u8) ?ProviderInfo

fn hasVersionedApiSegment(url: []const u8) bool

fn isValidCustomProviderUrl(url: []const u8) bool

fn isLocalEndpoint(url: []const u8) bool

fn providerRequiresApiKeyForSetup(provider: []const u8, base_url: ?[]const u8) bool

    const canonical = canonicalProviderName(provider);





/// Resolve a provider name used in quick setup.
/// Accepts aliases (e.g. "grok" -> "xai") and returns provider metadata.
/// Supports custom: prefix for OpenAI-compatible endpoints.
pub fn resolveProviderForQuickSetup(name: []const u8) ?ProviderInfo


/// Resolve a memory backend key for quick setup.
/// Distinguishes "unknown key" from "known but disabled in this build".
pub fn resolveMemoryBackendForQuickSetup(name: []const u8) ResolveMemoryBackendError!*const memory_root.BackendDescriptor

/// Get the default model for a provider.
pub fn defaultModelForProvider(provider: []const u8) []const u8

fn writeOnboardingNextSteps(out: anytype, api_key_env_hint: ?[]const u8) !void

/// Get the environment variable name for a provider's API key.
pub fn providerEnvVar(provider: []const u8) []const u8

// ── Live model fetching ─────────────────────────────────────────

pub const ModelsCacheEntry = struct {

/// Hardcoded fallback models for each provider (used when API fetch fails).
pub fn fallbackModelsForProvider(provider: []const u8) []const []const u8

const ProviderFallback = struct {

    var rows: [known_providers.len]ProviderFallback = undefined;

fn providerDefaultFallback(provider: []const u8) ?[]const []const u8



const MAX_MODELS = 20;
const MODELS_DEV_URL = "https://models.dev/api.json";

const ModelsDevProvider = struct {


/// Return a heap-allocated copy of the static fallback list for a provider.
/// Caller owns the returned slice and all its strings.
fn dupeFallbackModels(allocator: std.mem.Allocator, provider: []const u8) ![][]const u8

/// Fetch available model IDs for a provider (with caching, limit, and fallback).
///
/// Uses file-based cache at `~/.nullclaw/state/models_cache.json` with 12h TTL.
/// Returns at most 20 model IDs. Caller ALWAYS owns the returned slice and strings.
/// Free with: for (models) |m| allocator.free(m); allocator.free(models);
pub fn fetchModels(allocator: std.mem.Allocator, provider: []const u8, api_key: ?[]const u8) ![][]const u8

/// Fetch model IDs from a provider's API. Returns owned slice of owned strings.
/// Native list endpoints are preferred when available. For providers without a
/// native listing API, or when setup lacks credentials, production builds fall
/// back to the public models.dev catalog before using hardcoded defaults.
/// Results are limited to MAX_MODELS entries.
pub fn fetchModelsFromApi(allocator: std.mem.Allocator, provider: []const u8, api_key: ?[]const u8) ![][]const u8

fn fetchModelsFromNativeApi(allocator: std.mem.Allocator, canonical: []const u8, api_key: ?[]const u8) !?[][]const u8

fn modelsDevProviderKey(provider: []const u8) ?[]const u8

fn shouldUseModelsDevCatalog(provider: []const u8, api_key: ?[]const u8) bool

fn modelsCacheProviderKey(allocator: std.mem.Allocator, provider: []const u8, api_key: ?[]const u8) ![]const u8

fn fetchModelsFromModelsDev(allocator: std.mem.Allocator, provider: []const u8) !?[][]const u8

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_response, .{

fn modelsDevModelSupportsChat(model_id: []const u8, model_val: std.json.Value) bool

fn jsonStringArrayContains(value: std.json.Value, needle: []const u8) bool

fn prioritizeDefaultModel(models: [][]const u8, default_model: []const u8) void

fn fetchAndParseModels(allocator: std.mem.Allocator, url: []const u8, headers: []const []const u8, prefix_filter: ?[]const u8) ![][]const u8

/// Build the models endpoint URL for an OpenAI-compatible API.
/// Given a base URL like "https://api.example.com/v1", returns "https://api.example.com/v1/models".
/// If the URL already ends with "/models", returns a duplicate of the input.
/// Caller owns the returned string.
fn buildModelsUrl(allocator: std.mem.Allocator, base_url: []const u8) ![]const u8

/// Load models with file-based cache. Cache expires after 12 hours.
/// Falls back to hardcoded list on any error. Caller ALWAYS owns the result.
pub fn loadModelsWithCache(allocator: std.mem.Allocator, cache_dir: []const u8, provider: []const u8, api_key: ?[]const u8) ![][]const u8

fn loadModelsWithCacheInner(allocator: std.mem.Allocator, cache_dir: []const u8, provider: []const u8, api_key: ?[]const u8) ![][]const u8

const CACHE_TTL_SECS: i64 = 12 * 3600; // 12 hours

fn readCachedModels(allocator: std.mem.Allocator, cache_path: []const u8, provider: []const u8) ![][]const u8

fn saveCachedModels(allocator: std.mem.Allocator, cache_path: []const u8, provider: []const u8, models: []const []const u8) !void

/// Parse a mock OpenRouter-style JSON response and extract model IDs.
/// Used for testing the JSON parsing logic without network access.
pub fn parseModelIds(allocator: std.mem.Allocator, json_response: []const u8) ![][]const u8

// ── Fresh config with arena ──────────────────────────────────────

/// Create a fresh Config backed by an arena (for when Config.load() fails).
/// Caller must call cfg.deinit() when done.
pub fn initFreshConfig(backing_allocator: std.mem.Allocator) !Config

// ── Quick setup ──────────────────────────────────────────────────

/// Non-interactive setup: generates a sensible default config.
pub fn runQuickSetup(allocator: std.mem.Allocator, api_key: ?[]const u8, provider: ?[]const u8, model: ?[]const u8, memory_backend: ?[]const u8) !void

/// Main entry point — called from main.zig as `onboard.run(allocator)`.
pub fn run(allocator: std.mem.Allocator) !void

fn ensureSecretsEncryptionEnabled(cfg: *const Config) Config.ValidationError!void

/// Reconfigure channels and allowlists only (preserves existing config).
pub fn runChannelsOnly(allocator: std.mem.Allocator) !void

const StdinLineReader = struct {

var stdin_line_reader = StdinLineReader{