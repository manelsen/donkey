/// Config schema types (agents, channels, tools, session, gateway, plugins).
/// Corresponds to `src/config/types.ts` and `zod-schema.*.ts` in the TS codebase.
use std::collections::HashMap;

use {
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
};

// ── Reasoning effort ──────────────────────────────────────────────────────

/// Reasoning/thinking effort level for models that support extended thinking.
///
/// Maps to provider-specific parameters:
/// - **Anthropic**: `thinking.budget_tokens` (low=4096, medium=10240, high=32768)
/// - **OpenAI**: `reasoning_effort` field on o-series models
/// - **Other providers**: ignored if unsupported
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ReasoningEffort {
    ...
}

/// Agent identity (name, emoji, theme).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct AgentIdentity {
    ...
}

/// IANA timezone (e.g. `"Europe/Paris"`).
///
/// Wraps [`chrono_tz::Tz`] and (de)serialises as a plain string so it stays
/// compatible with the YAML frontmatter in `USER.md`.
#[derive(Debug, Clone)]
pub struct Timezone(pub chrono_tz::Tz);

#[derive(Debug, thiserror::Error)]
#[error("unknown IANA timezone: {value}")]
pub struct TimezoneParseError {
    ...
}

impl Timezone {
    /// The IANA name, e.g. `"Europe/Paris"`.
    #[must_use]
    pub fn name(&self) -> &str {

    /// The inner [`chrono_tz::Tz`] value.
    #[must_use]
    pub fn tz(&self) -> chrono_tz::Tz {
    ...
}
}

impl std::fmt::Display for Timezone {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl std::str::FromStr for Timezone {
    type Err = TimezoneParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
}

impl From<chrono_tz::Tz> for Timezone {
    fn from(tz: chrono_tz::Tz) -> Self {
}

impl Serialize for Timezone {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
}

impl<'de> Deserialize<'de> for Timezone {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        s.parse::<Self>().map_err(serde::de::Error::custom)
    }
}

/// Geographic coordinates (WGS 84).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeoLocation {
    ...
}

impl GeoLocation {
    /// Create a new `GeoLocation` stamped with the current time.
    pub fn now(latitude: f64, longitude: f64, place: Option<String>) -> Self {
}

impl std::fmt::Display for GeoLocation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// User profile collected during onboarding.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct UserProfile {
    ...
}

/// Resolved identity combining agent identity and user profile.
/// Used as the API response for `identity_get` and in the gon data blob.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResolvedIdentity {
    ...
}

impl ResolvedIdentity {
    pub fn from_config(cfg: &MoltisConfig) -> Self {
}

impl Default for ResolvedIdentity {
    fn default() -> Self {
}

/// Root configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct MoltisConfig {
    ...
}

/// Agent spawn presets used by tools like `spawn_agent`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct AgentsConfig {
    ...
}

impl AgentsConfig {
    /// Return a preset by name.
    pub fn get_preset(&self, name: &str) -> Option<&AgentPreset> {
}

/// Tool policy for a preset (allow/deny specific tools).
///
/// When both `allow` and `deny` are specified, `allow` acts as a whitelist
/// and `deny` further removes tools from that list.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct PresetToolPolicy {
    ...
}

/// Scope for per-agent persistent memory.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MemoryScope {
    ...
}

/// Persistent memory configuration for a preset.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct PresetMemoryConfig {
    ...
}

impl Default for PresetMemoryConfig {
    fn default() -> Self {
}

/// Session access policy configuration for a preset.
///
/// Controls which sessions an agent can see and interact with via
/// the `sessions_list`, `sessions_history`, and `sessions_send` tools.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct SessionAccessPolicyConfig {
    ...
}

impl Default for SessionAccessPolicyConfig {
    fn default() -> Self {
}

/// Spawn policy preset for sub-agents.
///
/// Presets allow defining specialized agent configurations that can be
/// selected when spawning sub-agents. Each preset can override identity,
/// model, tool policies, and system prompt.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct AgentPreset {
    ...
}

/// Voice configuration (TTS and STT).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceConfig {
    ...
}

/// Voice TTS configuration for moltis.toml.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceTtsConfig {
    ...
}

impl Default for VoiceTtsConfig {
    fn default() -> Self {
}

/// ElevenLabs provider configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceElevenLabsConfig {
    ...
}

/// OpenAI TTS/STT provider configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceOpenAiConfig {
    ...
}

/// Google Cloud TTS provider configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceGoogleTtsConfig {
    ...
}

/// Piper TTS (local) configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoicePiperTtsConfig {
    ...
}

/// Coqui TTS (local server) configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceCoquiTtsConfig {
    ...
}

impl Default for VoiceCoquiTtsConfig {
    fn default() -> Self {
}

/// Voice STT configuration for moltis.toml.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceSttConfig {
    ...
}

impl Default for VoiceSttConfig {
    fn default() -> Self {
}

/// Speech-to-Text provider identifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VoiceSttProvider {
    ...
}

impl VoiceSttProvider {
    #[must_use]
    pub fn as_str(self) -> &'static str {

    #[must_use]
    pub fn parse(s: &str) -> Option<Self> {
    ...
}
}

impl std::fmt::Display for VoiceSttProvider {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// OpenAI Whisper configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceWhisperConfig {
    ...
}

/// Groq STT configuration (Whisper-compatible API).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceGroqSttConfig {
    ...
}

/// Deepgram STT configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceDeepgramConfig {
    ...
}

/// Google Cloud Speech-to-Text configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceGoogleSttConfig {
    ...
}

/// Mistral AI (Voxtral Transcribe) configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceMistralSttConfig {
    ...
}

/// ElevenLabs Scribe STT configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceElevenLabsSttConfig {
    ...
}

/// Voxtral local (vLLM server) configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceVoxtralLocalConfig {
    ...
}

impl Default for VoiceVoxtralLocalConfig {
    fn default() -> Self {
}

/// whisper-cli (whisper.cpp) configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceWhisperCliConfig {
    ...
}

/// sherpa-onnx offline configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceSherpaOnnxConfig {
    ...
}

/// Gateway server configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ServerConfig {
    ...
}

fn default_log_buffer_size() -> usize {
    ...
}

fn default_db_pool_max_connections() -> u32 {
    ...
}

impl Default for ServerConfig {
    fn default() -> Self {
}

/// Failover configuration for automatic model/provider failover.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct FailoverConfig {
    ...
}

impl Default for FailoverConfig {
    fn default() -> Self {
}

/// Heartbeat configuration — periodic health-check agent turn.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct HeartbeatConfig {
    ...
}

impl Default for HeartbeatConfig {
    fn default() -> Self {
}

/// Active hours window for heartbeats.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ActiveHoursConfig {
    ...
}

impl Default for ActiveHoursConfig {
    fn default() -> Self {
}

/// Cron scheduler configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct CronConfig {
    ...
}

impl Default for CronConfig {
    fn default() -> Self {
}

/// Channel webhook middleware configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct WebhooksConfig {
    ...
}

/// Rate limiting configuration for channel webhooks.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct WebhookRateLimitConfig {
    ...
}

impl Default for WebhookRateLimitConfig {
    fn default() -> Self {
}

/// CalDAV integration configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct CalDavConfig {
    ...
}

/// Configuration for a single CalDAV account.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct CalDavAccountConfig {
    ...
}

impl Default for CalDavAccountConfig {
    fn default() -> Self {
}

impl std::fmt::Debug for CalDavAccountConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

fn default_caldav_timeout() -> u64 {
    ...
}

/// Tailscale Serve/Funnel configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct TailscaleConfig {
    ...
}

impl Default for TailscaleConfig {
    fn default() -> Self {
}

/// Memory embedding provider configuration.
///
/// Controls which embedding provider the memory system uses.
/// If not configured, the system auto-detects from available providers.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct MemoryEmbeddingConfig {
    ...
}

/// QMD backend configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct QmdConfig {
    ...
}

/// A QMD collection configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct QmdCollection {
    ...
}

/// Hooks configuration section (shell hooks defined in config file).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HooksConfig {
    ...
}

/// A single shell hook defined in the config file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShellHookConfigEntry {
    ...
}

fn default_hook_timeout() -> u64 {
    ...
}

/// Authentication configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct AuthConfig {
    ...
}

/// Runtime GraphQL server configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct GraphqlConfig {
    ...
}

impl Default for GraphqlConfig {
    fn default() -> Self {
}

/// Metrics and observability configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct MetricsConfig {
    ...
}

fn default_metrics_history_points() -> usize {
    ...
}

impl Default for MetricsConfig {
    fn default() -> Self {
}

impl MoltisConfig {
    /// Returns `true` when both the agent name and user name have been set
    /// (i.e. the onboarding wizard has been completed).
    pub fn is_onboarded(&self) -> bool {
}

/// Skills configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct SkillsConfig {
    ...
}

fn default_true() -> bool {
    ...
}

/// MCP (Model Context Protocol) server configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct McpConfig {
    ...
}

/// Configuration for a single MCP server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpServerEntry {
    ...
}

/// Manual OAuth configuration override for an MCP server.
///
/// Used when the server doesn't implement RFC 9728/8414 discovery or
/// when dynamic client registration is not available.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpOAuthOverrideEntry {
    ...
}

/// Built-in channel type identifiers recognised by the validator.
///
/// Kept in `moltis-config` (not `moltis-channels`) so the config crate stays
/// independent of the channels crate while still validating channel names.
pub const KNOWN_CHANNEL_TYPES: &[&str] = &["telegram", "whatsapp", "msteams", "discord", "slack"];

/// Channel configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ChannelsConfig {
    ...
}

impl ChannelsConfig {
    /// All named channel fields as `(channel_type, accounts)` pairs.
    ///
    /// This is the single source of truth for the set of named channel types.
    /// Keep in sync with the struct fields.
    fn named_fields(&self) -> [(&str, &HashMap<String, serde_json::Value>); 5] {

    /// Iterate all channel configs (named + extra) as `(channel_type, accounts)` pairs.
    pub fn all_channel_configs(&self) -> Vec<(&str, &HashMap<String, serde_json::Value>)> {
    ...
}
}

fn default_channels_offered() -> Vec<String> {
    ...
}

impl Default for ChannelsConfig {
    fn default() -> Self {
}

/// TLS configuration for the gateway HTTPS server.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct TlsConfig {
    ...
}

impl Default for TlsConfig {
    fn default() -> Self {
}

/// Chat configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ChatConfig {
    ...
}

fn default_message_queue_mode() -> MessageQueueMode {
    ...
}

impl Default for ChatConfig {
    fn default() -> Self {
}

/// Behaviour when `chat.send()` is called during an active run.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MessageQueueMode {
    ...
}

/// Tools configuration (exec, sandbox, policy, web, browser).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ToolsConfig {
    ...
}

impl Default for ToolsConfig {
    fn default() -> Self {
}

fn default_agent_timeout_secs() -> u64 {
    ...
}

fn default_agent_max_iterations() -> usize {
    ...
}

fn default_max_tool_result_bytes() -> usize {
    ...
}

/// Map tools configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct MapsConfig {
    ...
}

/// Map provider selection for map links.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
pub enum MapProvider {
    ...
}

/// Web tools configuration (search, fetch).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct WebConfig {
    ...
}

/// Search provider selection.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SearchProvider {
    ...
}

/// Web search tool configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct WebSearchConfig {
    ...
}

impl Default for WebSearchConfig {
    fn default() -> Self {
}

/// Perplexity search provider configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct PerplexityConfig {
    ...
}

/// Web fetch tool configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct WebFetchConfig {
    ...
}

impl Default for WebFetchConfig {
    fn default() -> Self {
}

/// Browser automation configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct BrowserConfig {
    ...
}

fn default_sandbox_image() -> String {
    ...
}

const fn default_low_memory_threshold_mb() -> u64 {
    ...
}

const fn default_persist_profile() -> bool {
    ...
}

fn default_container_host() -> String {
    ...
}

impl Default for BrowserConfig {
    fn default() -> Self {
}

/// Exec tool configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ExecConfig {
    ...
}

impl Default for ExecConfig {
    fn default() -> Self {
}

/// Resource limits for sandboxed execution.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ResourceLimitsConfig {
    ...
}

/// Optional per-tool overrides for WASM fuel and memory.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ToolLimitOverrideConfig {
    ...
}

/// Configurable WASM tool limits.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct WasmToolLimitsConfig {
    ...
}

fn default_wasm_tool_overrides() -> HashMap<String, ToolLimitOverrideConfig> {
    ...
}

impl Default for WasmToolLimitsConfig {
    fn default() -> Self {
}

/// Persistence strategy for `/home/sandbox` in sandbox containers.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum HomePersistenceConfig {
    ...
}

/// Sandbox configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct SandboxConfig {
    ...
}

/// Default packages installed in sandbox containers.
/// Inspired by GitHub Actions runner images — covers commonly needed
/// CLI tools, language runtimes, and utilities for LLM-driven tasks.
fn default_sandbox_packages() -> Vec<String> {
    ...
}

impl Default for SandboxConfig {
    fn default() -> Self {
}

/// Tool policy configuration (allow/deny lists).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ToolPolicyConfig {
    ...
}

/// OAuth provider configuration (e.g. openai-codex).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthProviderConfig {
    ...
}

/// LLM provider configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ProvidersConfig {
    ...
}

/// How tool calling is handled for a provider.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ToolMode {
    ...
}

const fn is_default_tool_mode(v: &ToolMode) -> bool {
    ...
}

/// Streaming transport for provider response streams.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ProviderStreamTransport {
    ...
}

/// Configuration for a single LLM provider.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ProviderEntry {
    ...
}

impl std::fmt::Debug for ProviderEntry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for ProviderEntry {
    fn default() -> Self {
}

// ── Serde helpers for Secret<String> ────────────────────────────────────────

fn serialize_option_secret<S: serde::Serializer>(
    secret: &Option<Secret<String>>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    match secret {
        Some(s) => serializer.serialize_some(s.expose_secret()),
        None => serializer.serialize_none(),
    }
}

fn deserialize_option_secret<'de, D>(deserializer: D) -> Result<Option<Secret<String>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let opt: Option<String> = Option::deserialize(deserializer)?;
    Ok(opt.map(Secret::new))
}

const fn is_true(value: &bool) -> bool {
    ...
}

const fn is_default_provider_stream_transport(value: &ProviderStreamTransport) -> bool {
    ...
}

impl ProvidersConfig {
    fn normalize_provider_name(value: &str) -> String {

    fn provider_name_matches(left: &str, right: &str) -> bool {
    ...
}

    fn is_offered(&self, name: &str) -> bool {
    ...
}

    fn provider_entry(&self, name: &str) -> Option<&ProviderEntry> {
    ...
}

    /// Check if a provider is enabled (defaults to true if not configured).
    pub fn is_enabled(&self, name: &str) -> bool {
    ...
}

    /// Get the configured entry for a provider, if any.
    pub fn get(&self, name: &str) -> Option<&ProviderEntry> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn geolocation_display_without_place() {
    ...
}

    #[test]
    fn geolocation_serde_backward_compat() {
    ...
}

    #[test]
    fn geolocation_serde_with_place() {
    ...
}

    #[test]
    fn geolocation_now_stores_place() {
    ...
}

    #[test]
    fn env_section_parses() {
    ...
}

    #[test]
    fn env_section_defaults_to_empty() {
    ...
}

    #[test]
    fn agents_config_defaults_empty() {
    ...
}

    #[test]
    fn agents_config_parses_presets() {
    ...
}

    #[test]
    fn chat_config_default_queue_mode_is_followup() {
    ...
}

    #[test]
    fn chat_config_toml_missing_queue_mode_defaults_to_followup() {
    ...
}

    #[test]
    fn providers_config_local_alias_maps_local_llm_to_local() {
    ...
}

    #[test]
    fn providers_config_local_alias_prefers_exact_key() {
    ...
}

    #[test]
    fn providers_config_offered_controls_enablement() {
    ...
}

    #[test]
    fn providers_config_offered_handles_local_alias() {
    ...
}

    #[test]
    fn providers_config_enabled_flag_still_applies_with_offered_allowlist() {
    ...
}

    #[test]
    fn provider_entry_defaults_fetch_models_enabled() {
    ...
}

    #[test]
    fn channels_config_defaults_to_telegram_discord_slack_offered() {
    ...
}

    #[test]
    fn channels_config_empty_toml_defaults_offered() {
    ...
}

    #[test]
    fn channels_config_explicit_offered() {
    ...
}

    #[test]
    fn channels_slack_is_named_field_not_extra() {
    ...
}

    #[test]
    fn channels_all_channel_configs_includes_slack() {
    ...
}

    #[test]
    fn sandbox_defaults_include_go_runtime() {
    ...
}

    #[test]
    fn wasm_tool_limits_config_defaults() {
    ...
}

    #[test]
    fn sandbox_wasm_tool_limits_deserialize() {
    ...
}

    #[test]
    fn tool_mode_serde_round_trip() {
    ...
}

    #[test]
    fn tool_mode_toml_round_trip() {
    ...
}

    #[test]
    fn tool_mode_default_is_auto() {
    ...
}

    #[test]
    fn provider_entry_tool_mode_defaults_to_auto() {
    ...
}

    #[test]
    fn provider_entry_tool_mode_skipped_when_default() {
    ...
}

    #[test]
    fn provider_entry_tool_mode_persisted_when_non_default() {
    ...
}

    #[test]
    fn provider_entry_url_alias_maps_to_base_url() {
    ...
}

    #[test]
    fn memory_embedding_legacy_aliases_map_to_current_fields() {
    ...
}

    #[test]
    fn full_config_with_tool_mode() {
    ...
}
}
