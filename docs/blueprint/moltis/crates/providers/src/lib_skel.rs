//! LLM provider implementations and registry.

pub mod anthropic;
#[cfg(test)]
pub mod contract;
pub mod error;
pub mod openai;
pub mod openai_compat;
pub mod ws_pool;

#[cfg(feature = "provider-genai")]
pub mod genai_provider;

#[cfg(feature = "provider-async-openai")]
pub mod async_openai_provider;

#[cfg(feature = "provider-openai-codex")]
pub mod openai_codex;

#[cfg(feature = "provider-github-copilot")]
pub mod github_copilot;

#[cfg(feature = "provider-kimi-code")]
pub mod kimi_code;

#[cfg(feature = "local-llm")]
pub mod local_gguf;

#[cfg(feature = "local-llm")]
pub mod local_llm;

use std::{
    collections::{HashMap, HashSet},
    pin::Pin,
    sync::Arc,
};

use {
    moltis_config::schema::{ProviderStreamTransport, ProvidersConfig},
    secrecy::ExposeSecret,
    tokio_stream::Stream,
};

use moltis_agents::model::{ChatMessage, LlmProvider, StreamEvent};

/// Shared HTTP client for LLM providers.
///
/// All providers that don't need custom redirect/proxy settings should
/// reuse this client to share connection pools, DNS cache, and TLS sessions.
pub fn shared_http_client() -> &'static reqwest::Client {
    ...
}

/// A model discovered from a provider API (e.g. `/v1/models`).
///
/// Replaces bare `(String, String)` tuples so that optional metadata
/// such as `created_at` can travel alongside the id/display_name pair.
#[derive(Debug, Clone)]
pub struct DiscoveredModel {
    ...
}

impl DiscoveredModel {
    pub fn new(id: impl Into<String>, display_name: impl Into<String>) -> Self {

    pub fn with_created_at(mut self, created_at: Option<i64>) -> Self {
    ...
}
}

const MODEL_ID_NAMESPACE_SEP: &str = "::";

#[must_use]
pub fn namespaced_model_id(provider: &str, model_id: &str) -> String {
    ...
}

/// Separator between a model ID and its reasoning effort suffix.
const REASONING_SUFFIX_SEP: char = '@';

/// Reasoning effort suffixes appended to model IDs.
const REASONING_SUFFIXES: &[(&str, moltis_agents::model::ReasoningEffort)] = &[
    ("reasoning-low", moltis_agents::model::ReasoningEffort::Low),
    (
        "reasoning-medium",
        moltis_agents::model::ReasoningEffort::Medium,
    ),
    (
        "reasoning-high",
        moltis_agents::model::ReasoningEffort::High,
    ),
];

/// Split a model ID into (base_id, optional reasoning effort).
///
/// Examples:
/// - `"anthropic::claude-opus-4-5@reasoning-high"` → `("anthropic::claude-opus-4-5", Some(High))`
/// - `"gpt-4o"` → `("gpt-4o", None)`
#[must_use]
pub fn split_reasoning_suffix(
    model_id: &str,
) -> (&str, Option<moltis_agents::model::ReasoningEffort>) {
    ...
}

#[must_use]
pub fn raw_model_id(model_id: &str) -> &str {
    ...
}

#[must_use]
fn capability_model_id(model_id: &str) -> &str {
    ...
}

fn configured_model_for_provider(model_id: &str) -> &str {
    ...
}

fn configured_models_for_provider(config: &ProvidersConfig, provider: &str) -> Vec<String> {
    ...
}

fn subscription_preference_rank(provider_name: &str) -> usize {
    ...
}

#[cfg_attr(
    not(any(feature = "provider-openai-codex", feature = "provider-github-copilot")),
    allow(dead_code)
)]
fn oauth_discovery_enabled(config: &ProvidersConfig, provider_name: &str) -> bool {
    ...
}

fn normalize_unique_models(models: impl IntoIterator<Item = String>) -> Vec<String> {
    ...
}

fn should_fetch_models(config: &ProvidersConfig, provider: &str) -> bool {
    ...
}

fn merge_preferred_and_discovered_models(
    preferred: Vec<String>,
    discovered: Vec<DiscoveredModel>,
) -> Vec<DiscoveredModel> {
    ...
}

fn merge_discovered_with_fallback_catalog(
    discovered: Vec<DiscoveredModel>,
    fallback: Vec<DiscoveredModel>,
) -> Vec<DiscoveredModel> {
    ...
}

fn normalize_ollama_api_base_url(base_url: &str) -> String {
    ...
}

/// Parse `Retry-After` header as milliseconds.
///
/// `Retry-After` may be either delta-seconds or an HTTP date. We currently
/// consume delta-seconds, which is what providers typically return for 429.
pub(crate) fn retry_after_ms_from_headers(headers: &reqwest::header::HeaderMap) -> Option<u64> {
    ...
}

/// Attach an explicit retry hint marker consumable by runner retry logic.
pub(crate) fn with_retry_after_marker(base: String, retry_after_ms: Option<u64>) -> String {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct OllamaTagEntry {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct OllamaTagsPayload {
    ...
}

async fn discover_ollama_models_from_api(base_url: String) -> anyhow::Result<Vec<DiscoveredModel>> {
    ...
}

/// Spawn Ollama model discovery in a background thread and return the receiver
/// immediately, without blocking. Call `.recv()` later to collect the result.
fn start_ollama_discovery(
    base_url: &str,
) -> std::sync::mpsc::Receiver<anyhow::Result<Vec<DiscoveredModel>>> {
    ...
}

// ── Ollama model info probing ────────────────────────────────────────────────

#[derive(Debug, Default, serde::Deserialize)]
struct OllamaShowResponse {
    ...
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
struct OllamaModelDetails {
    ...
}

/// Model families known to support native OpenAI-style tool calling in Ollama.
const OLLAMA_NATIVE_TOOL_FAMILIES: &[&str] = &[
    "llama3.1",
    "llama3.2",
    "llama3.3",
    "llama4",
    "qwen2.5",
    "qwen3",
    "mistral",
    "mixtral",
    "command-r",
    "firefunction",
    "hermes",
];

/// Determine whether an Ollama model supports native tool calling based on its
/// model name and family metadata from `/api/show`.
fn ollama_model_supports_native_tools(model_name: &str, details: &OllamaModelDetails) -> bool {
    ...
}

/// Check if Ollama's `capabilities` list indicates native tool support.
///
/// Returns `Some(true)` if `"tools"` is present, `Some(false)` if capabilities
/// exist but don't include tools, and `None` if the list is empty (pre-0.5.x
/// Ollama versions that don't report capabilities).
fn ollama_capabilities_support_tools(capabilities: &[String]) -> Option<bool> {
    ...
}

/// Probe the Ollama `/api/show` endpoint for a specific model to get its family
/// and details. Returns `Ok(response)` on success, error on timeout/failure.
async fn probe_ollama_model_info(
    base_url: &str,
    model_name: &str,
) -> anyhow::Result<OllamaShowResponse> {
    ...
}

/// Resolve the effective tool mode for an Ollama model.
///
/// - If the user configured an explicit `tool_mode`, use that.
/// - Otherwise, check the model's `capabilities` list from Ollama (>= 0.5.x).
/// - Fall back to the hardcoded family whitelist only when capabilities are
///   unavailable (pre-0.5.x Ollama).
fn resolve_ollama_tool_mode(
    config_tool_mode: moltis_config::ToolMode,
    model_name: &str,
    probe_result: Option<&OllamaShowResponse>,
) -> moltis_config::ToolMode {
    ...
}

/// Batch-probe Ollama `/api/show` for a list of models.
/// Runs probes in a dedicated thread with its own tokio runtime (same pattern
/// as `discover_ollama_models`). Returns a map from model ID to show response;
/// failures are silently dropped.
fn probe_ollama_models_batch(
    base_url: &str,
    models: &[DiscoveredModel],
) -> HashMap<String, OllamaShowResponse> {
    ...
}

struct RegistryModelProvider {
    ...
}

#[async_trait::async_trait]
impl LlmProvider for RegistryModelProvider {
    fn name(&self) -> &str {

    fn id(&self) -> &str {
    ...
}

    async fn complete(
        &self,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
    ) -> anyhow::Result<moltis_agents::model::CompletionResponse> {
    ...
}

    fn supports_tools(&self) -> bool {
    ...
}

    fn tool_mode(&self) -> Option<moltis_config::ToolMode> {
    ...
}

    fn context_window(&self) -> u32 {
    ...
}

    fn supports_vision(&self) -> bool {
    ...
}

    fn stream(
        &self,
        messages: Vec<ChatMessage>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

    fn stream_with_tools(
        &self,
        messages: Vec<ChatMessage>,
        tools: Vec<serde_json::Value>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

    fn reasoning_effort(&self) -> Option<moltis_agents::model::ReasoningEffort> {
    ...
}

    fn with_reasoning_effort(
        self: Arc<Self>,
        effort: moltis_agents::model::ReasoningEffort,
    ) -> Option<Arc<dyn LlmProvider>> {
    ...
}
}

/// Resolve an API key from config (Secret) or environment variable,
/// keeping the value wrapped in `Secret<String>` to avoid leaking it.
fn env_value(env_overrides: &HashMap<String, String>, key: &str) -> Option<String> {
    ...
}

/// Resolve an API key from config (Secret) or environment variable,
/// keeping the value wrapped in `Secret<String>` to avoid leaking it.
fn resolve_api_key(
    config: &ProvidersConfig,
    provider: &str,
    env_key: &str,
    env_overrides: &HashMap<String, String>,
) -> Option<secrecy::Secret<String>> {
    ...
}

/// Return the known context window size (in tokens) for a model ID.
/// Falls back to 200,000 for unknown models.
pub fn context_window_for_model(model_id: &str) -> u32 {
    ...
}

/// Returns `false` for model IDs that are clearly not chat-completion models
/// (image generators, TTS, speech-to-text, embeddings, moderation, etc.).
///
/// Provider APIs like OpenAI's `/v1/models` return every model in the account.
/// Since no capability metadata is exposed we filter by well-known prefixes and
/// patterns. This is applied both at discovery time and at display time so that
/// non-chat models never appear in the UI.
pub fn is_chat_capable_model(model_id: &str) -> bool {
    ...
}

/// Check if a model supports tool/function calling.
///
/// Most modern chat models support tools, but legacy completions-only models
/// (e.g. `babbage-002`, `davinci-002`) and non-chat models do not.
/// This is checked per-model rather than per-provider so that providers
/// exposing mixed catalogs report accurate tool support.
pub fn supports_tools_for_model(model_id: &str) -> bool {
    ...
}

/// Check if a model supports vision (image inputs).
///
/// Vision-capable models can process images in tool results and user messages.
/// When true, the runner sends images as multimodal content blocks rather than
/// stripping them from the context.
pub fn supports_vision_for_model(model_id: &str) -> bool {
    ...
}

/// Check if a model supports reasoning/extended thinking.
///
/// Reasoning-capable models can use the `reasoning_effort` configuration
/// to control the depth of extended thinking. This is used by the UI and
/// validation to inform users when reasoning_effort is set on a model
/// that doesn't support it.
pub fn supports_reasoning_for_model(model_id: &str) -> bool {
    ...
}

/// Info about an available model.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ModelInfo {
    ...
}

/// Known Anthropic Claude models (model_id, display_name).
/// Current models listed first, then legacy models.
const ANTHROPIC_MODELS: &[(&str, &str)] = &[
    ("claude-opus-4-5-20251101", "Claude Opus 4.5"),
    ("claude-sonnet-4-5-20250929", "Claude Sonnet 4.5"),
    ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ("claude-opus-4-1-20250805", "Claude Opus 4.1"),
    ("claude-sonnet-4-20250514", "Claude Sonnet 4"),
    ("claude-opus-4-20250514", "Claude Opus 4"),
    ("claude-3-7-sonnet-20250219", "Claude 3.7 Sonnet"),
    ("claude-3-haiku-20240307", "Claude 3 Haiku"),
];

/// Known Mistral models.
const MISTRAL_MODELS: &[(&str, &str)] = &[
    ("mistral-large-latest", "Mistral Large"),
    ("codestral-latest", "Codestral"),
];

/// Known Cerebras models.
const CEREBRAS_MODELS: &[(&str, &str)] =
    &[("llama-4-scout-17b-16e-instruct", "Llama 4 Scout (Cerebras)")];

/// Known MiniMax models.
/// See: <https://platform.minimax.io/docs/api-reference/text-anthropic-api>
const MINIMAX_MODELS: &[(&str, &str)] = &[
    ("MiniMax-M2.5", "MiniMax M2.5"),
    ("MiniMax-M2.5-highspeed", "MiniMax M2.5 Highspeed"),
    ("MiniMax-M2.1", "MiniMax M2.1"),
    ("MiniMax-M2", "MiniMax M2"),
];

/// Known Z.AI (Zhipu) models.
/// See: <https://docs.z.ai/api-reference/llm/chat-completion>
const ZAI_MODELS: &[(&str, &str)] = &[
    ("glm-5", "GLM-5"),
    ("glm-4.7", "GLM-4.7"),
    ("glm-4.7-flash", "GLM-4.7 Flash"),
    ("glm-4.7-flashx", "GLM-4.7 FlashX"),
    ("glm-4.6", "GLM-4.6"),
    ("glm-4.6v", "GLM-4.6V (Vision)"),
    ("glm-4.6v-flash", "GLM-4.6V Flash"),
    ("glm-4.5", "GLM-4.5"),
    ("glm-4.5-air", "GLM-4.5 Air"),
    ("glm-4.5-airx", "GLM-4.5 AirX"),
    ("glm-4.5-flash", "GLM-4.5 Flash"),
    ("glm-4.5v", "GLM-4.5V (Vision)"),
    ("glm-4-32b-0414-128k", "GLM-4 32B 128K"),
];

/// Known DeepSeek models.
const DEEPSEEK_MODELS: &[(&str, &str)] = &[
    ("deepseek-chat", "DeepSeek Chat"),
    ("deepseek-reasoner", "DeepSeek Reasoner"),
];

/// Known Moonshot models.
const MOONSHOT_MODELS: &[(&str, &str)] = &[("kimi-k2.5", "Kimi K2.5")];

/// Known Google Gemini models.
/// See: <https://ai.google.dev/gemini-api/docs/models>
const GEMINI_MODELS: &[(&str, &str)] = &[
    ("gemini-2.5-flash-preview-05-20", "Gemini 2.5 Flash Preview"),
    ("gemini-2.5-pro-preview-05-06", "Gemini 2.5 Pro Preview"),
    ("gemini-2.0-flash", "Gemini 2.0 Flash"),
    ("gemini-2.0-flash-lite", "Gemini 2.0 Flash Lite"),
];

/// OpenAI-compatible provider definition for table-driven registration.
struct OpenAiCompatDef {
    ...
}

const OPENAI_COMPAT_PROVIDERS: &[OpenAiCompatDef] = &[
    OpenAiCompatDef {
        config_name: "mistral",
        env_key: "MISTRAL_API_KEY",
        env_base_url_key: "MISTRAL_BASE_URL",
        default_base_url: "https://api.mistral.ai/v1",
        models: MISTRAL_MODELS,
        supports_model_discovery: true,
        requires_api_key: true,
        local_only: false,
    },
    OpenAiCompatDef {
        config_name: "openrouter",
        env_key: "OPENROUTER_API_KEY",
        env_base_url_key: "OPENROUTER_BASE_URL",
        default_base_url: "https://openrouter.ai/api/v1",
        models: &[],
        supports_model_discovery: true,
        requires_api_key: true,
        local_only: false,
    },
    OpenAiCompatDef {
        config_name: "cerebras",
        env_key: "CEREBRAS_API_KEY",
        env_base_url_key: "CEREBRAS_BASE_URL",
        default_base_url: "https://api.cerebras.ai/v1",
        models: CEREBRAS_MODELS,
        supports_model_discovery: true,
        requires_api_key: true,
        local_only: false,
    },
    OpenAiCompatDef {
        config_name: "minimax",
        env_key: "MINIMAX_API_KEY",
        env_base_url_key: "MINIMAX_BASE_URL",
        default_base_url: "https://api.minimax.io/v1",
        models: MINIMAX_MODELS,
        // MiniMax API does not expose a /models endpoint (returns 404).
        supports_model_discovery: false,
        requires_api_key: true,
        local_only: false,
    },
    OpenAiCompatDef {
        config_name: "moonshot",
        env_key: "MOONSHOT_API_KEY",
        env_base_url_key: "MOONSHOT_BASE_URL",
        default_base_url: "https://api.moonshot.ai/v1",
        models: MOONSHOT_MODELS,
        supports_model_discovery: true,
        requires_api_key: true,
        local_only: false,
    },
    OpenAiCompatDef {
        config_name: "zai",
        env_key: "Z_API_KEY",
        env_base_url_key: "Z_BASE_URL",
        default_base_url: "https://api.z.ai/api/paas/v4",
        models: ZAI_MODELS,
        supports_model_discovery: true,
        requires_api_key: true,
        local_only: false,
    },
    OpenAiCompatDef {
        config_name: "venice",
        env_key: "VENICE_API_KEY",
        env_base_url_key: "VENICE_BASE_URL",
        default_base_url: "https://api.venice.ai/api/v1",
        models: &[],
        supports_model_discovery: true,
        requires_api_key: true,
        local_only: false,
    },
    OpenAiCompatDef {
        config_name: "deepseek",
        env_key: "DEEPSEEK_API_KEY",
        env_base_url_key: "DEEPSEEK_BASE_URL",
        default_base_url: "https://api.deepseek.com",
        models: DEEPSEEK_MODELS,
        supports_model_discovery: true,
        requires_api_key: true,
        local_only: false,
    },
    OpenAiCompatDef {
        config_name: "ollama",
        env_key: "OLLAMA_API_KEY",
        env_base_url_key: "OLLAMA_BASE_URL",
        default_base_url: "http://127.0.0.1:11434/v1",
        models: &[],
        supports_model_discovery: true,
        requires_api_key: false,
        local_only: true,
    },
    OpenAiCompatDef {
        config_name: "lmstudio",
        env_key: "LMSTUDIO_API_KEY",
        env_base_url_key: "LMSTUDIO_BASE_URL",
        default_base_url: "http://127.0.0.1:1234/v1",
        models: &[],
        supports_model_discovery: true,
        requires_api_key: false,
        local_only: true,
    },
    OpenAiCompatDef {
        config_name: "gemini",
        env_key: "GEMINI_API_KEY",
        env_base_url_key: "GEMINI_BASE_URL",
        default_base_url: "https://generativelanguage.googleapis.com/v1beta/openai",
        models: GEMINI_MODELS,
        supports_model_discovery: true,
        requires_api_key: true,
        local_only: false,
    },
];

#[cfg(any(feature = "provider-openai-codex", feature = "provider-github-copilot"))]
trait DynamicModelDiscovery {
    fn provider_name(&self) -> &'static str;
    fn is_enabled_and_authenticated(&self, config: &ProvidersConfig) -> bool;
    fn configured_models(&self, config: &ProvidersConfig) -> Vec<String>;
    fn should_fetch_models(&self, config: &ProvidersConfig) -> bool;
    fn live_models(&self) -> anyhow::Result<Vec<DiscoveredModel>>;
    fn build_provider(&self, model_id: String, config: &ProvidersConfig) -> Arc<dyn LlmProvider>;
    fn display_name(&self, model_id: &str, discovered: &str) -> String;
}

#[cfg(feature = "provider-openai-codex")]
struct OpenAiCodexDiscovery;

#[cfg(feature = "provider-openai-codex")]
impl DynamicModelDiscovery for OpenAiCodexDiscovery {
    ...
}

#[cfg(feature = "provider-github-copilot")]
struct GitHubCopilotDiscovery;

#[cfg(feature = "provider-github-copilot")]
impl DynamicModelDiscovery for GitHubCopilotDiscovery {
    fn provider_name(&self) -> &'static str {

    fn is_enabled_and_authenticated(&self, config: &ProvidersConfig) -> bool {
    ...
}

    fn configured_models(&self, config: &ProvidersConfig) -> Vec<String> {
    ...
}

    fn should_fetch_models(&self, config: &ProvidersConfig) -> bool {
    ...
}

    fn live_models(&self) -> anyhow::Result<Vec<DiscoveredModel>> {
    ...
}

    fn build_provider(&self, model_id: String, _config: &ProvidersConfig) -> Arc<dyn LlmProvider> {
    ...
}

    fn display_name(&self, _model_id: &str, discovered: &str) -> String {
    ...
}
}

/// Registry of available LLM providers, keyed by namespaced model ID.
pub struct ProviderRegistry {
    ...
}

/// Pending model discovery handles returned by [`ProviderRegistry::fire_discoveries`].
pub type PendingDiscoveries = Vec<(
    String,
    std::sync::mpsc::Receiver<anyhow::Result<Vec<DiscoveredModel>>>,
)>;

impl ProviderRegistry {
    #[must_use]
    pub fn empty() -> Self {

    fn has_provider_model(&self, provider: &str, model_id: &str) -> bool {
    ...
}

    /// Check if the raw (un-namespaced) model ID is registered under any provider.
    fn has_model_any_provider(&self, model_id: &str) -> bool {
    ...
}

    fn resolve_registry_model_id(
        &self,
        model_id: &str,
        provider_hint: Option<&str>,
    ) -> Option<String> {
    ...
}

    #[cfg(any(feature = "provider-openai-codex", feature = "provider-github-copilot"))]
    #[allow(clippy::vec_init_then_push)]
    fn dynamic_discovery_sources() -> Vec<Box<dyn DynamicModelDiscovery>> {
    ...
}

    #[cfg(any(feature = "provider-openai-codex", feature = "provider-github-copilot"))]
    fn desired_models_for_dynamic_source(
        source: &dyn DynamicModelDiscovery,
        config: &ProvidersConfig,
        catalog: Vec<DiscoveredModel>,
    ) -> Option<Vec<DiscoveredModel>> {
    ...
}

    #[cfg(any(feature = "provider-openai-codex", feature = "provider-github-copilot"))]
    fn register_dynamic_source_models(
        &mut self,
        source: &dyn DynamicModelDiscovery,
        config: &ProvidersConfig,
        catalog: Vec<DiscoveredModel>,
    ) {
    ...
}

    #[cfg(any(feature = "provider-openai-codex", feature = "provider-github-copilot"))]
    fn refresh_dynamic_source_models(
        &mut self,
        source: &dyn DynamicModelDiscovery,
        config: &ProvidersConfig,
    ) -> bool {
    ...
}

    /// Register a provider manually.
    pub fn register(&mut self, mut info: ModelInfo, provider: Arc<dyn LlmProvider>) {
    ...
}

    /// Unregister a provider by model ID. Returns true if it was removed.
    pub fn unregister(&mut self, model_id: &str) -> bool {
    ...
}

    /// Auto-discover providers from environment variables.
    /// Uses default config (all providers enabled).
    pub fn from_env() -> Self {
    ...
}

    /// Auto-discover providers from environment variables,
    /// respecting the given config for enable/disable and overrides.
    ///
    /// Provider registration order:
    /// 1. Built-in raw reqwest providers (always available, support tool calling)
    /// 2. async-openai-backed providers (if `provider-async-openai` feature enabled)
    /// 3. genai-backed providers (if `provider-genai` feature enabled, no tool support)
    /// 4. OpenAI Codex OAuth providers (if `provider-openai-codex` feature enabled)
    ///
    /// Model/provider auto-selection preference:
    /// 1. Subscription providers (`openai-codex`, `github-copilot`)
    /// 2. Everything else
    ///
    /// Within the same preference tier, registration order wins.
    pub fn from_env_with_config(config: &ProvidersConfig) -> Self {
    ...
}

    /// Auto-discover providers from config, process env, and optional env
    /// overrides. Process env always wins when both are present.
    ///
    /// Model discovery HTTP requests are fired concurrently in Phase 1,
    /// collected in Phase 2, and the results are used to register providers
    /// in Phase 3. This reduces startup time from `sum(latencies)` to
    /// `max(latencies)`.
    pub fn from_env_with_config_and_overrides(
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
    ) -> Self {
    ...
}

    /// Register providers without making any discovery HTTP requests.
    ///
    /// This uses static model catalogs plus any explicit/pinned models from
    /// config and env overrides.
    pub fn from_config_with_static_catalogs(
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
    ) -> Self {
    ...
}

    /// Register providers using already-collected discovery results.
    ///
    /// `prefetched` should come from [`collect_discoveries`], but callers may
    /// also pass an empty map to register only static catalogs.
    pub fn from_config_with_prefetched(
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
        prefetched: &HashMap<String, Vec<DiscoveredModel>>,
    ) -> Self {
    ...
}

    /// Fire all provider model discovery HTTP requests concurrently.
    ///
    /// Returns a vec of `(provider_key, Receiver)` handles. Each receiver
    /// will eventually yield the discovered model list. Call
    /// [`collect_discoveries`] to drain them (blocking).
    #[allow(unused_mut)] // `pending` may be unused when features are disabled
    pub fn fire_discoveries(
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
    ) -> PendingDiscoveries {
    ...
}

    /// Drain all pending discovery receivers (blocking on each `recv()`).
    ///
    /// Returns a map from provider name to discovered models.
    pub fn collect_discoveries(
        pending: PendingDiscoveries,
    ) -> HashMap<String, Vec<DiscoveredModel>> {
    ...
}

    #[cfg(feature = "provider-genai")]
    fn register_genai_providers(
        &mut self,
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
    ) {
    ...
}

    #[cfg(feature = "provider-async-openai")]
    fn register_async_openai_providers(
        &mut self,
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
    ) {
    ...
}

    #[cfg(feature = "provider-openai-codex")]
    fn register_openai_codex_providers(
        &mut self,
        config: &ProvidersConfig,
        prefetched: &HashMap<String, Vec<DiscoveredModel>>,
    ) {
    ...
}

    pub fn refresh_openai_codex_models(&mut self, config: &ProvidersConfig) -> bool {
    ...
}

    #[cfg(feature = "provider-github-copilot")]
    fn register_github_copilot_providers(
        &mut self,
        config: &ProvidersConfig,
        prefetched: &HashMap<String, Vec<DiscoveredModel>>,
    ) {
    ...
}

    pub fn refresh_github_copilot_models(&mut self, config: &ProvidersConfig) -> bool {
    ...
}

    pub fn refresh_dynamic_models(&mut self, config: &ProvidersConfig) -> Vec<(String, bool)> {
    ...
}

    #[cfg(feature = "provider-kimi-code")]
    fn register_kimi_code_providers(
        &mut self,
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
    ) {
    ...
}

    #[cfg(feature = "local-llm")]
    fn register_local_gguf_providers(&mut self, config: &ProvidersConfig) {
    ...
}

    fn register_builtin_providers(
        &mut self,
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
        prefetched: &HashMap<String, Vec<DiscoveredModel>>,
    ) {
    ...
}

    fn register_openai_compatible_providers(
        &mut self,
        config: &ProvidersConfig,
        env_overrides: &HashMap<String, String>,
        prefetched: &HashMap<String, Vec<DiscoveredModel>>,
    ) {
    ...
}

    /// Register custom OpenAI-compatible providers (names starting with `custom-`).
    /// These are user-added endpoints that may support model discovery via `/v1/models`.
    fn register_custom_providers(
        &mut self,
        config: &ProvidersConfig,
        prefetched: &HashMap<String, Vec<DiscoveredModel>>,
    ) {
    ...
}

    pub fn get(&self, model_id: &str) -> Option<Arc<dyn LlmProvider>> {
    ...
}

    pub fn first(&self) -> Option<Arc<dyn LlmProvider>> {
    ...
}

    /// Return the first provider that supports tool calling,
    /// falling back to the first provider overall.
    pub fn first_with_tools(&self) -> Option<Arc<dyn LlmProvider>> {
    ...
}

    pub fn list_models(&self) -> &[ModelInfo] {
    ...
}

    /// Return the base model list plus reasoning-effort variants for supported models.
    ///
    /// For each model that supports extended thinking, three additional entries
    /// are appended: `<id>@reasoning-low`, `<id>@reasoning-medium`, `<id>@reasoning-high`.
    /// These virtual IDs are resolved by `get()` back to the base provider with
    /// the corresponding reasoning effort applied.
    #[must_use]
    pub fn list_models_with_reasoning_variants(&self) -> Vec<ModelInfo> {
    ...
}

    /// Return all registered providers in registration order.
    pub fn all_providers(&self) -> Vec<Arc<dyn LlmProvider>> {
    ...
}

    /// Return providers for the given model IDs (in order), skipping unknown IDs.
    pub fn providers_for_models(&self, model_ids: &[String]) -> Vec<Arc<dyn LlmProvider>> {
    ...
}

    /// Return fallback providers ordered by affinity to the given primary:
    ///
    /// 1. Same model ID on a different provider backend (e.g. `gpt-4o` via openrouter)
    /// 2. Subscription providers (`openai-codex`, `github-copilot`)
    /// 3. Other models from the same provider (e.g. `claude-opus-4` when primary is `claude-sonnet-4`)
    /// 4. Models from other providers
    ///
    /// The primary itself is excluded from the result.
    pub fn fallback_providers_for(
        &self,
        primary_model_id: &str,
        primary_provider_name: &str,
    ) -> Vec<Arc<dyn LlmProvider>> {
    ...
}

    pub fn is_empty(&self) -> bool {
    ...
}

    pub fn provider_summary(&self) -> String {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn context_window_for_known_models() {
    ...
}

    #[test]
    fn context_window_fallback_for_unknown_model() {
    ...
}

    #[test]
    fn oauth_discovery_enabled_ignores_offered_allowlist() {
    ...
}

    #[test]
    fn oauth_discovery_enabled_respects_explicit_disable() {
    ...
}

    #[test]
    fn provider_context_window_uses_lookup() {
    ...
}

    #[test]
    fn supports_vision_for_known_models() {
    ...
}

    #[test]
    fn supports_vision_false_for_non_vision_models() {
    ...
}

    #[test]
    fn provider_supports_vision_uses_lookup() {
    ...
}

    #[test]
    fn is_chat_capable_filters_non_chat_models() {
    ...
}

    #[test]
    fn supports_tools_for_chat_models() {
    ...
}

    #[test]
    fn supports_tools_false_for_legacy_and_non_chat_models() {
    ...
}

    #[test]
    fn provider_supports_tools_uses_model_lookup() {
    ...
}

    #[test]
    fn default_context_window_trait() {
    ...
}

    #[test]
    fn merge_discovered_with_fallback_keeps_discovered_when_non_empty() {
    ...
}

    #[test]
    fn merge_discovered_with_fallback_uses_fallback_when_discovered_empty() {
    ...
}

    #[test]
    fn model_lists_not_empty() {
    ...
}

    #[test]
    fn model_lists_have_unique_ids() {
    ...
}

    #[test]
    fn openai_compat_providers_have_unique_names() {
    ...
}

    #[test]
    fn openai_compat_providers_have_valid_urls() {
    ...
}

    #[test]
    fn openai_compat_providers_env_keys_not_empty() {
    ...
}

    #[test]
    fn registry_from_env_does_not_panic() {
    ...
}

    #[test]
    fn registry_register_and_get() {
    ...
}

    #[cfg(feature = "provider-openai-codex")]
    #[test]
    fn refresh_openai_codex_models_is_noop_when_disabled() {
    ...
}

    #[test]
    fn mistral_registers_with_api_key() {
    ...
}

    #[test]
    fn cerebras_registers_with_api_key() {
    ...
}

    #[test]
    fn minimax_registers_with_api_key() {
    ...
}

    #[test]
    fn minimax_registers_with_env_override_api_key() {
    ...
}

    #[test]
    fn openai_registers_with_generic_provider_env_override() {
    ...
}

    #[test]
    fn zai_registers_with_api_key() {
    ...
}

    #[test]
    fn moonshot_registers_with_api_key() {
    ...
}

    #[test]
    fn deepseek_registers_with_api_key() {
    ...
}

    #[test]
    fn openrouter_requires_model_in_config() {
    ...
}

    #[test]
    fn openrouter_registers_with_model_in_config() {
    ...
}

    #[test]
    fn openrouter_strips_foreign_namespace_in_config_model_ids() {
    ...
}

    #[test]
    fn ollama_registers_without_api_key_env() {
    ...
}

    #[test]
    fn venice_requires_model_in_config() {
    ...
}

    #[test]
    fn disabled_provider_not_registered() {
    ...
}

    #[test]
    fn provider_name_returned_by_openai_provider() {
    ...
}

    #[test]
    fn custom_base_url_from_config() {
    ...
}

    #[test]
    fn provider_models_can_disable_fetch_and_pin_single_model() {
    ...
}

    #[test]
    fn provider_models_are_ordered_before_discovered_catalog() {
    ...
}

    #[test]
    fn fallback_providers_ordering() {
    ...
}

    #[test]
    fn raw_model_lookup_prefers_subscription_provider() {
    ...
}

    #[test]
    fn first_with_tools_prefers_subscription_provider() {
    ...
}

    #[test]
    fn fallback_prefers_subscription_before_same_provider_non_subscription_models() {
    ...
}

    #[cfg(feature = "local-llm")]
    #[test]
    fn local_llm_requires_model_in_config() {
    ...
}

    #[cfg(feature = "local-llm")]
    #[test]
    fn local_llm_registers_with_model_in_config() {
    ...
}

    #[cfg(feature = "local-llm")]
    #[test]
    fn local_llm_disabled_not_registered() {
    ...
}

    #[cfg(feature = "local-llm")]
    #[test]
    fn local_llm_alias_key_registers_model() {
    ...
}

    #[cfg(feature = "local-llm")]
    #[test]
    fn local_llm_alias_key_respects_disabled_flag() {
    ...
}

    // ── Vision Support Tests (Extended) ────────────────────────────────

    #[test]
    fn supports_vision_for_all_claude_variants() {
    ...
}

    #[test]
    fn supports_vision_for_all_gpt4o_variants() {
    ...
}

    #[test]
    fn supports_vision_for_gpt5_series() {
    ...
}

    #[test]
    fn supports_vision_for_o3_o4_series() {
    ...
}

    #[test]
    fn supports_vision_for_gemini_variants() {
    ...
}

    #[test]
    fn no_vision_for_text_only_models() {
    ...
}

    #[test]
    fn vision_support_is_case_sensitive() {
    ...
}

    #[test]
    fn vision_support_requires_exact_prefix() {
    ...
}

    // ── Ollama tool detection ────────────────────────────────────────────

    #[test]
    fn ollama_native_tools_known_families() {
    ...
}

    #[test]
    fn ollama_native_tools_qwen_family() {
    ...
}

    #[test]
    fn ollama_native_tools_unknown_family() {
    ...
}

    #[test]
    fn ollama_native_tools_name_heuristic() {
    ...
}

    #[test]
    fn resolve_ollama_tool_mode_explicit_override() {
    ...
}

    #[test]
    fn resolve_ollama_tool_mode_auto_with_probe() {
    ...
}

    #[test]
    fn resolve_ollama_tool_mode_auto_unknown_model() {
    ...
}

    // ── Ollama capabilities-based tool detection ──────────────────────

    #[test]
    fn ollama_capabilities_with_tools() {
    ...
}

    #[test]
    fn ollama_capabilities_without_tools() {
    ...
}

    #[test]
    fn ollama_capabilities_empty_returns_none() {
    ...
}

    #[test]
    fn resolve_ollama_tool_mode_capabilities_override_family() {
    ...
}

    #[test]
    fn resolve_ollama_tool_mode_capabilities_no_tools() {
    ...
}

    #[test]
    fn resolve_ollama_tool_mode_empty_capabilities_falls_back_to_family() {
    ...
}

    #[test]
    fn resolve_ollama_tool_mode_no_probe_result_falls_back_to_name_heuristic() {
    ...
}

    #[test]
    fn resolve_ollama_tool_mode_explicit_overrides_capabilities() {
    ...
}

    /// Verify OllamaShowResponse deserializes from Ollama >= 0.5.x JSON with capabilities.
    #[test]
    fn ollama_show_response_deserializes_with_capabilities() {
    ...
}

    /// Verify OllamaShowResponse deserializes from old Ollama without capabilities field.
    #[test]
    fn ollama_show_response_deserializes_without_capabilities() {
    ...
}

    /// Capabilities with only "tools" (single item).
    #[test]
    fn ollama_capabilities_single_tools_entry() {
    ...
}

    #[test]
    fn openai_provider_supports_tools_respects_override() {
    ...
}

    #[test]
    fn openai_provider_tool_mode_returns_override() {
    ...
}

    #[test]
    fn openai_provider_tool_mode_default_is_none() {
    ...
}

    #[test]
    fn split_reasoning_suffix_parses_effort_levels() {
    ...
}

    #[test]
    fn raw_model_id_strips_reasoning_suffix() {
    ...
}

    #[test]
    fn registry_get_resolves_reasoning_suffix() {
    ...
}

    #[test]
    fn list_models_with_reasoning_variants_generates_entries() {
    ...
}

    #[test]
    fn supports_reasoning_for_known_models() {
    ...
}
}
