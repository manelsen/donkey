const std = @import("std");
const search_base_url = @import("search_base_url.zig");
const tunnel_mod = @import("tunnel.zig");

/// Default context token budget used by agent compaction/context management.
/// Runtime fallback (`DEFAULT_CONTEXT_TOKENS`).
pub const DEFAULT_AGENT_TOKEN_LIMIT: u64 = 200_000;
/// Default generation cap when model/provider metadata does not define max output.
/// Runtime fallback (`DEFAULT_MODEL_MAX_TOKENS`).
pub const DEFAULT_MODEL_MAX_TOKENS: u32 = 8192;

// ── Autonomy Level ──────────────────────────────────────────────

/// Re-exported from security/policy.zig — single source of truth (with methods).
pub const AutonomyLevel = @import("security/policy.zig").AutonomyLevel;

// ── Hardware Transport ──────────────────────────────────────────

pub const HardwareTransport = enum {

// ── Sandbox Backend ─────────────────────────────────────────────

pub const SandboxBackend = enum {

// ── Provider entry (for "providers" config section) ─────────────

pub const ProviderEntry = struct {
    /// Provider credential payload.
    /// Usually a string API key/token.
    /// For providers that support structured credentials (e.g. Vertex service-account JSON),
    /// the parser accepts object/array JSON and stores it as a compact JSON string.
    /// Whether this provider supports native OpenAI-style tool_calls.
    /// Set to false to use XML tool format via system prompt instead.
    /// Optional User-Agent header for HTTP requests to this provider.
    /// When set, requests will include "User-Agent: {value}" header.

// ── Audio media config (tools.media.audio) ─────────────────────

pub const AudioMediaConfig = struct {

// ── Sub-config structs ──────────────────────────────────────────

pub const DiagnosticsConfig = struct {
    /// Optional max length for user-visible provider/API errors after scrubbing.
    /// If null, uses env var NULLCLAW_MAX_ERROR_CHARS (or built-in default).
    /// Emit info logs for every executed tool call (name/id/duration/success).
    /// Arguments and tool output are never logged.
    /// Emit info logs when a user message is received by SessionManager.
    /// Only metadata is logged (channel/session hash/message size), not content.
    /// Emit full inbound/outbound user-visible message payloads.
    /// Intended for local debugging only (can include sensitive text).
    /// Emit request/response payloads around provider chat calls.
    /// Intended for local debugging only (can include sensitive text).
    /// Persist per-response token counters to a JSONL ledger near config.json.
    /// This stores token counts only (provider/model/prompt/completion/total), not message text.
    /// Reset token usage ledger after this many hours. 0 disables time-based reset.
    /// Maximum ledger file size before reset. 0 disables size-based reset.
    /// Maximum number of JSONL rows before reset. 0 disables row-limit reset.

pub const AutonomyConfig = struct {
    /// When true, skip the single-`&` shell-operator check so that bare
    /// `&` in URLs (e.g. `curl https://...?a=1&b=2`) is permitted.
    /// Additional directories (absolute paths) the agent may access beyond workspace_dir.
    /// Resolved via realpath at check time; system-critical paths are always blocked.

pub const DockerRuntimeConfig = struct {

pub const RuntimeConfig = struct {

pub const ModelFallbackEntry = struct {

pub const ReliabilityConfig = struct {

pub const SchedulerConfig = struct {
    /// Hard timeout for cron agent subprocess execution. 0 = no timeout.

// ── Tool filter groups ──────────────────────────────────────────

/// Controls which MCP tools are included in the schema sent to the LLM each turn.
///
/// Two modes:
///   - `always`:  tools matching `tools` patterns are always included (no keywords needed).
///   - `dynamic`: tools matching `tools` patterns are included only when the user message
///                contains at least one of the `keywords` (case-insensitive substring match).
///
/// Built-in (non-MCP) tools are always included regardless of filter groups.
/// If no filter groups are configured, all tools pass through unchanged.
pub const ToolFilterGroupMode = enum {

pub const ToolFilterGroup = struct {
    /// Glob patterns matched against tool names (e.g. "mcp_vikunja_*").
    /// Supports `*` wildcard only (prefix/suffix/infix).
    /// Keywords for `dynamic` mode — case-insensitive substring match against user message.
    /// Ignored when mode is `always`.

pub const AgentConfig = struct {
    /// Internal parse marker: true only when token_limit is explicitly set in config.
    /// Not serialized; used to distinguish override vs default fallback chain.
    /// Include emoji prefixes in `/status` output.
    /// Max seconds to wait for an LLM HTTP response (curl --max-time). 0 = no limit.
    /// Per-turn MCP tool filtering. Empty slice = no filtering (all tools included).
    /// See ToolFilterGroup for semantics.
    /// List of models that do not support image/vision input.
    /// When image markers are detected and the model is in this list,
    /// the agent will skip processing images instead of returning an error.
    /// When true, automatically adds the current model to vision_disabled_models
    /// upon receiving a "model does not support vision" error.

pub const ToolsConfig = struct {
    /// Environment variables whose values are platform path-list strings.
    /// Each path component is validated against workspace + allowed_paths
    /// using the same sandbox rules as file access (system blocklist,
    /// realpath canonicalization). Only vars where ALL path components
    /// resolve within allowed areas are passed to shell child processes.
    ///
    /// Example: ["LD_LIBRARY_PATH", "PYTHONHOME", "NODE_PATH"]

pub const ModelRouteCostClass = enum {

pub const ModelRouteQuotaClass = enum {

pub const ModelRouteConfig = struct {

pub const HeartbeatConfig = struct {

pub const CronConfig = struct {

// ── Channel configs ─────────────────────────────────────────────

pub const TelegramInteractiveConfig = struct {

pub const TelegramReactionEmojisConfig = struct {

pub const TelegramCommandsMenuMode = enum {

pub const MaxListenerMode = enum {

pub const MaxInteractiveConfig = struct {

pub const MaxConfig = struct {

pub const TelegramConfig = struct {
    /// Use reply-to in private (1:1) chats. Groups always use reply-to.
    /// Optional SOCKS5/HTTP proxy URL for all Telegram API requests (e.g. "socks5://host:port").
    /// When true, only respond to messages that @mention the bot (in groups).
    /// Stream partial responses to users via sendMessageDraft before the final message.
    /// Show task lifecycle on the triggering user message via Telegram reactions.
    /// Per-state reaction emoji overrides. Empty string clears the reaction for that state.
    /// Enable Telegram-specific binding commands such as /bind.
    /// Enable Telegram-specific topic management commands such as /topic.
    /// Enable Telegram-specific topic/session map command such as /topics.
    /// Publish Telegram slash-command menu:
    /// off = clear it, flat = one global list, scoped = separate private/group menus.

pub const DiscordConfig = struct {

pub const SlackReceiveMode = enum {

pub const SlackReplyToMode = enum {
    /// Only thread when the triggering message is already a thread reply
    /// (thread_ts present and differs from ts). Default.
    /// Always reply in a thread, using thread_ts if present or message ts otherwise.

pub const SlackConfig = struct {

pub const TeamsConfig = struct {

pub const WebhookConfig = struct {

pub const IMessageConfig = struct {

pub const MatrixConfig = struct {

pub const MattermostConfig = struct {

pub const WhatsAppConfig = struct {

pub const IrcConfig = struct {

pub const LarkReceiveMode = enum {

pub const LarkConfig = struct {

pub const DingTalkConfig = struct {

pub const SignalConfig = struct {

pub const EmailConfig = struct {

pub const LineConfig = struct {

pub const QQGroupPolicy = enum {

pub const QQReceiveMode = enum {

pub const QQConfig = struct {

pub const OneBotConfig = struct {

pub const MaixCamConfig = struct {

pub const WebConfig = struct {
    /// "local" starts an inbound WS listener in nullclaw.
    /// "relay" keeps a single outbound WS connection to a relay service.
    /// Max bytes allowed for the HTTP upgrade request headers during WS handshake.
    /// Increase this when running behind reverse proxies that append many headers.
    /// Optional WebSocket-upgrade auth token for browser/extension clients.
    /// Used for WebSocket-upgrade hardening and for `message_auth_mode="token"`.
    /// If null, WebChannel falls back to env (NULLCLAW_WEB_TOKEN/NULLCLAW_GATEWAY_TOKEN/OPENCLAW_GATEWAY_TOKEN),
    /// then to an ephemeral runtime token.
    /// Authentication mode for inbound user_message events.
    /// - "pairing": require UI JWT access_token from pairing flow.
    /// - "token": require channel auth token in auth_token (or access_token for compatibility).
    /// Optional allowlist for Origin header values (exact match, supports "*").
    /// Empty = allow any origin.
    /// Relay endpoint for transport="relay" (must be wss://...).
    /// Stable logical agent identity on relay side.
    /// Optional dedicated relay auth token.
    /// If omitted, relay lifecycle resolves token from NULLCLAW_RELAY_TOKEN,
    /// then persisted `web-relay-<account_id>` credential, then generates one.
    /// Expiry for persisted relay token lifecycle (seconds).
    /// One-time pairing code lifetime for relay UI binding (seconds).
    /// UI access token (JWT) TTL in relay mode (seconds).
    /// Require E2E payload encryption for relay user_message events.

pub const NostrConfig = struct {
    /// Private key: must be enc2:-encrypted via SecretStore (use onboarding wizard or SecretStore.encryptSecret).
    /// Not required when bunker_uri is set (external bunker handles signing).
    /// Owner's public key — must be 64-char lowercase hex (not npub). Always allowed through DM policy.
    /// Bot's own public key — must be 64-char lowercase hex. Derived from private_key during onboarding.
    /// Used as the -p filter for the listener so incoming gift wraps reach the bot, not the owner.
    /// Empty string means not set (old config — re-run onboarding to populate).
    /// Relay URLs for publishing and subscribing.
    /// Relay URLs announced in kind:10050 (NIP-17 DM inbox).
    /// Senders look up this event to know where to address gift-wrapped DMs.
    /// The listener subscribes here in addition to `relays`, so the bot
    /// receives DMs on whichever relay the sender used.
    /// Pubkeys allowed to send DMs. Empty = deny all. ["*"] = allow all.
    /// Owner is always implicitly allowed regardless of this list.
    /// Display name for kind:0 metadata.
    /// About text for kind:0 metadata.
    /// Path to profile picture file. Published in kind:0 metadata as "picture" field.
    /// LNURL for Lightning Network & Cashu zaps (NIP-57). Published in kind:0 metadata as "lud16" field.
    /// NIP-05 identifier (e.g. "user@domain.com"). Published in kind:0 metadata as "nip05" field.
    /// Path to the nak binary.
    /// Bunker URI (auto-populated at first start, or manually set for external bunker).
    /// Directory containing the config file and .secret_key.
    /// Set at construction time by the config loader or onboarding wizard.
    /// Used by vtableStart to instantiate SecretStore for key decryption.

pub const ChannelsConfig = struct {

// ── Memory config ───────────────────────────────────────────────

/// Memory configuration profile presets.
pub const MemoryProfile = enum {
    /// Hybrid: SQLite backend with workspace bootstrap files.
    /// SQLite keyword-only (default).
    /// File-based markdown memory.
    /// PostgreSQL keyword-only.
    /// SQLite + vector hybrid.
    /// PostgreSQL + vector hybrid.
    /// Stateless no-op.
    /// Custom — no profile defaults applied.

pub const MemoryConfig = struct {
    /// Profile preset — convenience shortcut for common setups.
    /// Apply profile defaults. Only sets fields that are still at their default values,
    /// so explicit user overrides always win (profile is applied AFTER parsing).

pub const MemorySearchConfig = struct {

pub const MemoryQmdConfig = struct {

pub const QmdIndexPath = struct {

pub const QmdMcporterConfig = struct {

pub const QmdSessionConfig = struct {

pub const QmdUpdateConfig = struct {

pub const QmdLimitsConfig = struct {

pub const MemoryVectorStoreConfig = struct {
    // sqlite_ann (experimental): candidate prefilter tuning.

pub const MemoryChunkingConfig = struct {

pub const MemorySyncConfig = struct {

pub const MemoryQueryConfig = struct {

pub const MemoryHybridConfig = struct {

pub const MemoryMmrConfig = struct {

pub const MemoryTemporalDecayConfig = struct {

pub const MemoryEmbeddingCacheConfig = struct {

pub const MemoryLifecycleConfig = struct {

pub const MemoryResponseCacheConfig = struct {

pub const MemoryReliabilityConfig = struct {
    /// Fallback policy when optional subsystems (vector plane, cache) fail to init.
    /// "degrade" (default): silently disable the failed subsystem, log a warning.
    /// "fail_fast": return null from initRuntime, preventing startup.

pub const MemoryPostgresConfig = struct {

pub const MemoryRedisConfig = struct {

pub const MemoryApiConfig = struct {

pub const MemoryClickHouseConfig = struct {
    /// Plain HTTP is accepted only for loopback hosts; remote endpoints must use HTTPS.

pub const MemoryRetrievalStagesConfig = struct {

pub const MemorySummarizerConfig = struct {

// ── Tunnel config ───────────────────────────────────────────────

// Re-export tunnel config types from tunnel.zig so config parsing stays
// aligned with the runtime tunnel factory shape.
pub const CloudflareTunnelConfig = tunnel_mod.CloudflareTunnelConfig;
pub const TailscaleTunnelConfig = tunnel_mod.TailscaleTunnelConfig;
pub const NgrokTunnelConfig = tunnel_mod.NgrokTunnelConfig;
pub const CustomTunnelConfig = tunnel_mod.CustomTunnelConfig;
pub const TunnelConfig = tunnel_mod.TunnelFullConfig;

// ── Gateway config ──────────────────────────────────────────────

pub const GatewayConfig = struct {

// ── A2A (Agent-to-Agent) protocol config ────────────────────────

pub const A2aConfig = struct {

// ── Composio config ─────────────────────────────────────────────

pub const ComposioConfig = struct {

// ── Secrets config ──────────────────────────────────────────────

pub const SecretsConfig = struct {

// ── Browser config ──────────────────────────────────────────────

pub const BrowserComputerUseConfig = struct {

pub const BrowserConfig = struct {

// ── HTTP request config ─────────────────────────────────────────

pub const HttpRequestConfig = struct {
    /// Optional outbound proxy URL used for provider/network curl requests.
    /// Supported schemes: http://, https://, socks5://
    /// Optional SearXNG instance URL used by web_search as a fallback when
    /// BRAVE_API_KEY is not available.
    /// HTTPS is allowed for any host. Plain HTTP is allowed only for local or
    /// private hosts such as localhost, .local names, or private IP ranges.
    /// Examples:
    ///   - "https://searx.example.com"
    ///   - "http://localhost:8888"
    ///   - "https://searx.example.com/search"
    /// Search provider for web_search.
    /// Supported: auto, searxng, duckduckgo (ddg), brave, firecrawl,
    /// tavily, perplexity, exa, jina.
    /// Optional fallback provider chain used when the primary provider fails.
    /// Validate optional SearXNG base URL accepted by web_search.
    /// Allowed forms:
    ///   - https://host
    ///   - https://host/search
    ///   - http://localhost[:port]
    ///   - http://localhost[:port]/search

// ── Identity config ─────────────────────────────────────────────

pub const IdentityConfig = struct {

// ── Cost config ─────────────────────────────────────────────────

pub const CostConfig = struct {

// ── Peripherals config ──────────────────────────────────────────

pub const PeripheralBoardConfig = struct {

pub const PeripheralsConfig = struct {

// ── Hardware config ─────────────────────────────────────────────

pub const HardwareConfig = struct {

// ── Security sub-configs ────────────────────────────────────────

pub const SandboxConfig = struct {

pub const ResourceLimitsConfig = struct {

pub const AuditConfig = struct {

pub const SecurityConfig = struct {

// ── Delegate agent config ───────────────────────────────────────

pub const DelegateAgentConfig = struct {

// ── Named agent config (for agents map in JSON) ────────────────

pub const NamedAgentConfig = struct {
    /// Runtime-only source path preserved so Config.save() can round-trip file-backed prompts.

// ── MCP Server Config ──────────────────────────────────────────

pub const McpServerConfig = struct {
    /// Per-request wall clock timeout for HTTP transport. 0 = default.

// ── Model Pricing ──────────────────────────────────────────────

pub const ModelPricing = struct {

// ── Session Config ──────────────────────────────────────────────

pub const DmScope = enum {
    /// Single shared session for all DMs.
    /// One session per peer across all channels.
    /// One session per (channel, peer) pair (default).
    /// One session per (account, channel, peer) triple.

pub const IdentityLink = struct {

pub const SessionConfig = struct {
    /// Maximum concurrent message processing tasks per channel.
    /// When set to 0 or 1, messages are processed sequentially.
    /// Higher values enable parallel processing across different sessions.

test "WebConfig defaults" {
    const cfg = WebConfig{

test "security defaults stay least-privilege" {
    const diagnostics = DiagnosticsConfig{

test "McpServerConfig transport validation" {

test "McpServerConfig http url validation" {

test "McpServerConfig timeout defaults" {
    const cfg = McpServerConfig{

test "McpServerConfig header validation" {

test "HttpRequestConfig proxy URL validation" {

test "WebConfig normalizePath trims and normalizes" {

test "WebConfig token validation enforces printable no-whitespace constraints" {

test "WebConfig origin validation accepts wildcard and absolute origins" {

test "WebConfig transport validation supports local and relay" {

test "WebConfig message auth mode validation supports pairing and token" {

test "WebConfig relay URL validation requires wss authority" {

test "WebConfig relay agent id validation enforces non-empty id" {

test "WebConfig relay ttl validation enforces documented ranges" {



test "HttpRequestConfig search base URL validation" {



test "HttpRequestConfig search provider validation" {

test "HttpRequestConfig fallback provider validation disallows auto" {
