use std::{
    collections::{BTreeSet, HashMap},
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use secrecy::{ExposeSecret, Secret};

use {
    async_trait::async_trait,
    serde_json::{Map, Value},
    tokio::sync::{OnceCell, RwLock},
    tracing::{debug, info, warn},
};

pub mod error;

use {
    moltis_config::schema::ProvidersConfig,
    moltis_oauth::{
        CallbackServer, OAuthFlow, TokenStore, callback_port, device_flow, load_oauth_config,
        parse_callback_input,
    },
    moltis_providers::{ProviderRegistry, raw_model_id},
};

use moltis_service_traits::{ProviderSetupService, ServiceError, ServiceResult};

/// Callback for publishing events to connected clients.
///
/// The gateway wires this up to its WebSocket broadcast mechanism so the
/// provider-setup crate doesn't depend on the gateway's internal types.
#[async_trait]
pub trait SetupBroadcaster: Send + Sync {
    async fn broadcast(&self, topic: &str, payload: Value);
}

// ── Key store ──────────────────────────────────────────────────────────────

/// Per-provider stored configuration (API key, base URL, preferred models).
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderConfig {
    ...
}

fn deserialize_provider_models<'de, D>(deserializer: D) -> Result<Vec<String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let value: Value = serde::Deserialize::deserialize(deserializer)?;
    let normalized = match value {
        Value::Null => Vec::new(),
        Value::String(model) => vec![model],
        Value::Array(values) => values
            .into_iter()
            .filter_map(|value| value.as_str().map(ToString::to_string))
            .collect(),
        _ => {
            return Err(serde::de::Error::custom(
                "models must be a string or string array",
            ));
        },
    };

    Ok(normalize_model_list(normalized))
}

fn normalize_model_list(models: impl IntoIterator<Item = String>) -> Vec<String> {
    ...
}

fn parse_models_param(params: &Value) -> Vec<String> {
    ...
}

fn progress_payload(value: Value) -> Map<String, Value> {
    ...
}

struct ProviderSetupTiming {
    ...
}

impl ProviderSetupTiming {
    fn start(operation: &'static str, provider: Option<&str>) -> Self {
}

impl Drop for ProviderSetupTiming {
    fn drop(&mut self) {
}

/// File-based provider config storage at `~/.config/moltis/provider_keys.json`.
/// Stores per-provider configuration including API keys, base URLs, and models.
#[derive(Debug, Clone)]
pub struct KeyStore {
    ...
}

#[derive(Debug)]
struct KeyStoreInner {
    ...
}

impl Default for KeyStore {
    fn default() -> Self {
}

impl KeyStore {
    pub fn new() -> Self {

    fn with_path(path: PathBuf) -> Self {
    ...
}

    fn lock(&self) -> std::sync::MutexGuard<'_, KeyStoreInner> {
    ...
}

    fn path(&self) -> PathBuf {
    ...
}

    /// Load all provider configs. Handles migration from old format (string values).
    fn load_all_configs_from_path(path: &PathBuf) -> HashMap<String, ProviderConfig> {
    ...
}

    pub fn load_all_configs(&self) -> HashMap<String, ProviderConfig> {
    ...
}

    /// Save all provider configs to disk.
    fn save_all_configs_to_path(
        path: &PathBuf,
        configs: &HashMap<String, ProviderConfig>,
    ) -> error::Result<()> {
    ...
}

    /// Load all API keys (used in tests).
    #[cfg_attr(not(test), allow(dead_code))]
    fn load_all(&self) -> HashMap<String, String> {
    ...
}

    /// Load a provider's API key.
    fn load(&self, provider: &str) -> Option<String> {
    ...
}

    /// Load a provider's full config.
    pub fn load_config(&self, provider: &str) -> Option<ProviderConfig> {
    ...
}

    /// Remove a provider's configuration.
    fn remove(&self, provider: &str) -> error::Result<()> {
    ...
}

    /// Save a provider's API key (simple interface, used in tests).
    #[cfg_attr(not(test), allow(dead_code))]
    fn save(&self, provider: &str, api_key: &str) -> error::Result<()> {
    ...
}

    /// Save a provider's full configuration.
    pub fn save_config(
        &self,
        provider: &str,
        api_key: Option<String>,
        base_url: Option<String>,
        models: Option<Vec<String>>,
    ) -> error::Result<()> {
    ...
}

    /// Save a provider's full configuration, including an optional display name.
    fn save_config_with_display_name(
        &self,
        provider: &str,
        api_key: Option<String>,
        base_url: Option<String>,
        models: Option<Vec<String>>,
        display_name: Option<String>,
    ) -> error::Result<()> {
    ...
}
}

// ── Helpers ────────────────────────────────────────────────────────────────

/// Merge persisted provider configs into a ProvidersConfig so the registry rebuild
/// picks them up without needing env vars.
pub fn config_with_saved_keys(
    base: &ProvidersConfig,
    key_store: &KeyStore,
    local_model_ids: &[String],
) -> ProvidersConfig {
    ...
}

// ── Custom provider helpers ────────────────────────────────────────────────

const CUSTOM_PROVIDER_PREFIX: &str = "custom-";

fn is_custom_provider(name: &str) -> bool {
    ...
}

/// Derive a provider name from a URL, e.g. `https://api.together.ai/v1` → `custom-together-ai`.
fn derive_provider_name_from_url(raw: &str) -> Option<String> {
    ...
}

/// Return a unique provider name by appending `-2`, `-3`, etc. if the base
/// name is already taken.
fn make_unique_provider_name(base: &str, existing: &HashMap<String, ProviderConfig>) -> String {
    ...
}

/// Extract a human-friendly display name from a URL.
/// `https://api.together.ai/v1` → `together.ai`
fn base_url_to_display_name(raw: &str) -> String {
    ...
}

fn normalize_base_url_for_compare(raw: &str) -> String {
    ...
}

fn existing_custom_provider_for_base_url(
    base_url: &str,
    existing: &HashMap<String, ProviderConfig>,
) -> Option<String> {
    ...
}

fn validation_provider_name_for_endpoint(
    provider_name: &str,
    provider_default_base_url: Option<&str>,
    base_url: Option<&str>,
) -> String {
    ...
}

const OLLAMA_DEFAULT_BASE_URL: &str = "http://localhost:11434";

fn normalize_ollama_openai_base_url(base_url: Option<&str>) -> String {
    ...
}

fn normalize_ollama_api_base_url(base_url: Option<&str>) -> String {
    ...
}

fn normalize_ollama_model_id(model: &str) -> &str {
    ...
}

fn ollama_model_matches(installed_model: &str, requested_model: &str) -> bool {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct OllamaTagsModel {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct OllamaTagsResponse {
    ...
}

async fn discover_ollama_models(base_url: &str) -> error::Result<Vec<String>> {
    ...
}

fn ollama_models_payload(models: &[String]) -> Vec<Value> {
    ...
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthType {
    ...
}

impl AuthType {
    pub const fn as_str(self) -> &'static str {
}

impl std::fmt::Display for AuthType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// Known provider definitions used to populate the "available providers" list.
pub struct KnownProvider {
    ...
}

/// Build the known providers list at runtime, including local-llm if enabled.
pub fn known_providers() -> Vec<KnownProvider> {
    ...
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AutoDetectedProviderSource {
    ...
}

fn current_config_dir() -> PathBuf {
    ...
}

fn home_config_dir_if_different() -> Option<PathBuf> {
    ...
}

fn home_key_store() -> Option<(KeyStore, PathBuf)> {
    ...
}

fn home_token_store() -> Option<(TokenStore, PathBuf)> {
    ...
}

fn home_provider_config() -> Option<(ProvidersConfig, PathBuf)> {
    ...
}

fn codex_cli_auth_path() -> Option<PathBuf> {
    ...
}

fn codex_cli_auth_has_access_token(path: &Path) -> bool {
    ...
}

/// Parse Codex CLI `auth.json` content into `OAuthTokens`.
fn parse_codex_cli_tokens(data: &str) -> Option<moltis_oauth::OAuthTokens> {
    ...
}

/// Import auto-detected external OAuth tokens into the token store so all
/// providers read from a single location. Currently handles Codex CLI
/// `~/.codex/auth.json` → `openai-codex` in the token store.
pub fn import_detected_oauth_tokens(
    detected: &[AutoDetectedProviderSource],
    token_store: &TokenStore,
) {
    ...
}

fn set_provider_enabled_in_config(provider: &str, enabled: bool) -> ServiceResult<()> {
    ...
}

fn normalize_provider_name(value: &str) -> String {
    ...
}

fn env_value_with_overrides(env_overrides: &HashMap<String, String>, key: &str) -> Option<String> {
    ...
}

fn ui_offered_provider_order(config: &ProvidersConfig) -> Vec<String> {
    ...
}

fn ui_offered_provider_set(offered_order: &[String]) -> Option<BTreeSet<String>> {
    ...
}

pub fn has_explicit_provider_settings(config: &ProvidersConfig) -> bool {
    ...
}

pub fn detect_auto_provider_sources_with_overrides(
    config: &ProvidersConfig,
    deploy_platform: Option<&str>,
    env_overrides: &HashMap<String, String>,
) -> Vec<AutoDetectedProviderSource> {
    ...
}

/// Function that parses a raw error string into a structured error object.
pub type ErrorParser = fn(&str, Option<&str>) -> Value;

/// Default error parser that wraps the raw error text in a JSON object.
fn default_error_parser(raw: &str, _provider: Option<&str>) -> Value {
    ...
}

pub struct LiveProviderSetupService {
    ...
}

#[derive(Clone)]
struct PendingOAuthFlow {
    ...
}

impl LiveProviderSetupService {
    pub fn new(
        registry: Arc<RwLock<ProviderRegistry>>,
        config: ProvidersConfig,
        deploy_platform: Option<String>,
    ) -> Self {

    pub fn with_env_overrides(mut self, env_overrides: HashMap<String, String>) -> Self {
    ...
}

    /// Set a custom error parser for interpreting provider API errors.
    pub fn with_error_parser(mut self, parser: ErrorParser) -> Self {
    ...
}

    /// Set the bind address for the OAuth callback server.
    ///
    /// Defaults to `127.0.0.1`. Pass `0.0.0.0` when the gateway is
    /// bound to all interfaces (e.g. Docker) so the OAuth callback port
    /// is reachable from the host.
    pub fn with_callback_bind_addr(mut self, addr: String) -> Self {
    ...
}

    /// Wire the shared priority models handle from `LiveModelService` so
    /// `save_model` can update dropdown ordering at runtime.
    pub fn set_priority_models(&mut self, handle: Arc<RwLock<Vec<String>>>) {
    ...
}

    /// Set the broadcaster so validation can publish live progress events
    /// to the UI over WebSocket.
    pub fn set_broadcaster(&self, broadcaster: Arc<dyn SetupBroadcaster>) {
    ...
}

    async fn emit_validation_progress(
        &self,
        provider: &str,
        request_id: Option<&str>,
        phase: &str,
        mut extra: Map<String, Value>,
    ) {
    ...
}

    fn queue_registry_rebuild(&self, provider_name: &str, reason: &'static str) {
    ...
}

    fn config_snapshot(&self) -> ProvidersConfig {
    ...
}

    fn set_provider_enabled_in_memory(&self, provider: &str, enabled: bool) {
    ...
}

    fn is_provider_configured(
        &self,
        provider: &KnownProvider,
        active_config: &ProvidersConfig,
    ) -> bool {
    ...
}

    /// Start a device-flow OAuth for providers like GitHub Copilot.
    /// Returns `{ "userCode": "...", "verificationUri": "..." }` for the UI to display.
    async fn oauth_start_device_flow(
        &self,
        provider_name: String,
        oauth_config: moltis_oauth::OAuthConfig,
    ) -> ServiceResult {
    ...
}

    /// Build a ProvidersConfig that includes saved keys for registry rebuild.
    fn effective_config(&self) -> ProvidersConfig {
    ...
}

    fn build_registry(&self, config: &ProvidersConfig) -> ProviderRegistry {
    ...
}

    fn has_oauth_tokens(&self, provider_name: &str) -> bool {
    ...
}
}

fn has_oauth_tokens_for_provider(
    provider_name: &str,
    primary_store: &TokenStore,
    home_store: Option<&TokenStore>,
) -> bool {
    ...
}

/// Build provider-specific extra headers for device-flow OAuth calls.
fn build_provider_headers(provider: &str) -> Option<reqwest::header::HeaderMap> {
    ...
}

/// Some providers require visiting a URL that already embeds the user_code.
/// Prefer provider-returned `verification_uri_complete`; otherwise synthesize
/// one for known providers.
fn build_verification_uri_complete(
    provider: &str,
    verification_uri: &str,
    user_code: &str,
    provided_complete: Option<String>,
) -> Option<String> {
    ...
}

#[async_trait]
impl ProviderSetupService for LiveProviderSetupService {
    async fn available(&self) -> ServiceResult {

    async fn save_key(&self, params: Value) -> ServiceResult {
    ...
}

    async fn oauth_start(&self, params: Value) -> ServiceResult {
    ...
}

    async fn oauth_complete(&self, params: Value) -> ServiceResult {
    ...
}

    async fn remove_key(&self, params: Value) -> ServiceResult {
    ...
}

    async fn oauth_status(&self, params: Value) -> ServiceResult {
    ...
}

    async fn validate_key(&self, params: Value) -> ServiceResult {
    ...
}

    async fn save_model(&self, params: Value) -> ServiceResult {
    ...
}

    async fn save_models(&self, params: Value) -> ServiceResult {
    ...
}

    async fn add_custom(&self, params: Value) -> ServiceResult {
    ...
}
}

// ── Validation probe ordering ────────────────────────────────────────────────

/// Reorder models so that known-fast, reliable models appear first for
/// validation probing.  We only need *one* successful response to prove the
/// API key works, so prefer the cheapest/fastest endpoints.
fn reorder_models_for_validation(models: &mut [moltis_providers::ModelInfo]) {
    ...
}

fn probe_priority_rank(model_id: &str, fast: &[&str], slow: &[&str]) -> u8 {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn known_providers_have_valid_auth_types() {
    ...
}

    #[test]
    fn api_key_providers_have_env_key() {
    ...
}

    #[test]
    fn oauth_providers_have_no_env_key() {
    ...
}

    #[test]
    fn local_providers_have_no_env_key() {
    ...
}

    #[test]
    fn known_provider_names_unique() {
    ...
}

    #[test]
    fn normalize_ollama_openai_base_url_appends_v1() {
    ...
}

    #[test]
    fn normalize_ollama_api_base_url_strips_v1() {
    ...
}

    #[test]
    fn ollama_model_matches_accepts_tag_suffix() {
    ...
}

    #[test]
    fn verification_uri_complete_prefers_provider_payload() {
    ...
}

    #[test]
    fn verification_uri_complete_synthesizes_for_kimi() {
    ...
}

    #[test]
    fn verification_uri_complete_synthesizes_with_existing_query() {
    ...
}

    #[test]
    fn provider_headers_include_kimi_device_headers() {
    ...
}

    #[test]
    fn provider_headers_are_none_for_non_kimi() {
    ...
}

    #[test]
    fn key_store_save_and_load() {
    ...
}

    #[test]
    fn key_store_path_reports_backing_file() {
    ...
}

    #[test]
    fn key_store_invalid_json_returns_empty_map() {
    ...
}
