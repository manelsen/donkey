//! Service trait interfaces for domain services.
//!
//! Each trait has a `Noop` implementation that returns empty/default responses,
//! allowing the gateway to run standalone before domain crates are wired in.

use {async_trait::async_trait, serde_json::Value, tracing::warn};

/// Error type returned by service methods.
#[derive(Debug, thiserror::Error)]
pub enum ServiceError {
    ...
}

impl ServiceError {
    #[must_use]
    pub fn message(message: impl std::fmt::Display) -> Self {

    #[must_use]
    pub fn forbidden(message: impl std::fmt::Display) -> Self {
    ...
}
}

impl From<String> for ServiceError {
    fn from(value: String) -> Self {
}

impl From<&str> for ServiceError {
    fn from(value: &str) -> Self {
}

impl From<ServiceError> for moltis_protocol::ErrorShape {
    fn from(err: ServiceError) -> Self {
}

pub type ServiceResult<T = Value> = Result<T, ServiceError>;

// ── Agent ───────────────────────────────────────────────────────────────────

#[async_trait]
pub trait AgentService: Send + Sync {
    async fn run(&self, params: Value) -> ServiceResult;
    async fn run_wait(&self, params: Value) -> ServiceResult;
    async fn identity_get(&self) -> ServiceResult;
    async fn list(&self) -> ServiceResult;
}

pub struct NoopAgentService;

#[async_trait]
impl AgentService for NoopAgentService {
    ...
}

// ── Sessions ────────────────────────────────────────────────────────────────

#[async_trait]
pub trait SessionService: Send + Sync {
    async fn list(&self) -> ServiceResult;
    async fn preview(&self, params: Value) -> ServiceResult;
    async fn resolve(&self, params: Value) -> ServiceResult;
    async fn patch(&self, params: Value) -> ServiceResult;
    async fn voice_generate(&self, params: Value) -> ServiceResult;
    async fn share_create(&self, params: Value) -> ServiceResult;
    async fn share_list(&self, params: Value) -> ServiceResult;
    async fn share_revoke(&self, params: Value) -> ServiceResult;
    async fn reset(&self, params: Value) -> ServiceResult;
    async fn delete(&self, params: Value) -> ServiceResult;
    async fn compact(&self, params: Value) -> ServiceResult;
    async fn search(&self, params: Value) -> ServiceResult;
    async fn fork(&self, params: Value) -> ServiceResult;
    async fn branches(&self, params: Value) -> ServiceResult;
    async fn run_detail(&self, params: Value) -> ServiceResult;
    async fn clear_all(&self) -> ServiceResult;
    async fn mark_seen(&self, key: &str);
}

pub struct NoopSessionService;

#[async_trait]
impl SessionService for NoopSessionService {
    ...
}

// ── Channels ────────────────────────────────────────────────────────────────

#[async_trait]
pub trait ChannelService: Send + Sync {
    async fn status(&self) -> ServiceResult;
    async fn logout(&self, params: Value) -> ServiceResult;
    async fn send(&self, params: Value) -> ServiceResult;
    async fn add(&self, params: Value) -> ServiceResult;
    async fn remove(&self, params: Value) -> ServiceResult;
    async fn update(&self, params: Value) -> ServiceResult;
    async fn senders_list(&self, params: Value) -> ServiceResult;
    async fn sender_approve(&self, params: Value) -> ServiceResult;
    async fn sender_deny(&self, params: Value) -> ServiceResult;
}

pub struct NoopChannelService;

#[async_trait]
impl ChannelService for NoopChannelService {
    ...
}

// ── Config ──────────────────────────────────────────────────────────────────

#[async_trait]
pub trait ConfigService: Send + Sync {
    async fn get(&self, params: Value) -> ServiceResult;
    async fn set(&self, params: Value) -> ServiceResult;
    async fn apply(&self, params: Value) -> ServiceResult;
    async fn patch(&self, params: Value) -> ServiceResult;
    async fn schema(&self) -> ServiceResult;
}

pub struct NoopConfigService;

#[async_trait]
impl ConfigService for NoopConfigService {
    ...
}

// ── Cron ────────────────────────────────────────────────────────────────────

#[async_trait]
pub trait CronService: Send + Sync {
    async fn list(&self) -> ServiceResult;
    async fn status(&self) -> ServiceResult;
    async fn add(&self, params: Value) -> ServiceResult;
    async fn update(&self, params: Value) -> ServiceResult;
    async fn remove(&self, params: Value) -> ServiceResult;
    async fn run(&self, params: Value) -> ServiceResult;
    async fn runs(&self, params: Value) -> ServiceResult;
}

pub struct NoopCronService;

#[async_trait]
impl CronService for NoopCronService {
    ...
}

// ── Chat ────────────────────────────────────────────────────────────────────

#[async_trait]
pub trait ChatService: Send + Sync {
    async fn send(&self, params: Value) -> ServiceResult;
    /// Run a chat send synchronously (inline, no spawn) and return token usage.
    /// Returns ` {
    ...
}

pub struct NoopChatService;

#[async_trait]
impl ChatService for NoopChatService {
    async fn send(&self, _p: Value) -> ServiceResult {

    async fn abort(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn cancel_queued(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn history(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn inject(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn clear(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn compact(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn context(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn raw_prompt(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn full_context(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn active(&self, _p: Value) -> ServiceResult {
    ...
}
}

// ── TTS ─────────────────────────────────────────────────────────────────────

#[async_trait]
pub trait TtsService: Send + Sync {
    async fn status(&self) -> ServiceResult;
    async fn providers(&self) -> ServiceResult;
    async fn enable(&self, params: Value) -> ServiceResult;
    async fn disable(&self) -> ServiceResult;
    async fn convert(&self, params: Value) -> ServiceResult;
    async fn set_provider(&self, params: Value) -> ServiceResult;
}

pub struct NoopTtsService;

#[async_trait]
impl TtsService for NoopTtsService {
    ...
}

// ── STT (Speech-to-Text) ────────────────────────────────────────────────────

#[async_trait]
pub trait SttService: Send + Sync {
    /// Get STT service status.
    async fn status(&self) -> ServiceResult;
    /// List available STT providers.
    async fn providers(&self) -> ServiceResult;
    /// Transcribe audio to text (base64-encoded audio in params).
    async fn transcribe(&self, params: Value) -> ServiceResult;
    /// Transcribe raw audio bytes directly (no base64 encoding needed).
    ///
    /// `format` is a short name like `"webm"`, `"ogg"`, `"mp3"` etc.
    async fn transcribe_bytes(
        &self,
        audio: bytes::Bytes,
        format: &str,
        provider: Option<&str>,
        language: Option<&str>,
        prompt: Option<&str>,
    ) -> ServiceResult;
    /// Set the active STT provider.
    async fn set_provider(&self, params: Value) -> ServiceResult;
}

pub struct NoopSttService;

#[async_trait]
impl SttService for NoopSttService {
    ...
}

// ── MCP (Model Context Protocol) ────────────────────────────────────────────

#[async_trait]
pub trait McpService: Send + Sync {
    /// List all configured MCP servers with status.
    async fn list(&self) -> ServiceResult;
    /// Add a new MCP server.
    async fn add(&self, params: Value) -> ServiceResult;
    /// Remove an MCP server.
    async fn remove(&self, params: Value) -> ServiceResult;
    /// Enable an MCP server.
    async fn enable(&self, params: Value) -> ServiceResult;
    /// Disable an MCP server.
    async fn disable(&self, params: Value) -> ServiceResult;
    /// Get status of a specific server.
    async fn status(&self, params: Value) -> ServiceResult;
    /// List tools from a specific server.
    async fn tools(&self, params: Value) -> ServiceResult;
    /// Restart an MCP server.
    async fn restart(&self, params: Value) -> ServiceResult;
    /// Update an MCP server's configuration.
    async fn update(&self, params: Value) -> ServiceResult;
    /// Trigger re-authentication for an SSE server.
    async fn reauth(&self, params: Value) -> ServiceResult;
    /// Start OAuth for an MCP SSE server.
    async fn oauth_start(&self, params: Value) -> ServiceResult;
    /// Complete an MCP OAuth callback.
    async fn oauth_complete(&self, params: Value) -> ServiceResult;
}

pub struct NoopMcpService;

#[async_trait]
impl McpService for NoopMcpService {
    ...
}

// ── Skills ──────────────────────────────────────────────────────────────────

#[async_trait]
pub trait SkillsService: Send + Sync {
    async fn status(&self) -> ServiceResult;
    async fn bins(&self) -> ServiceResult;
    async fn install(&self, params: Value) -> ServiceResult;
    async fn update(&self, params: Value) -> ServiceResult;
    async fn list(&self) -> ServiceResult;
    async fn remove(&self, params: Value) -> ServiceResult;
    async fn repos_list(&self) -> ServiceResult;
    /// Full repos list with per-skill details (for search). Heavyweight.
    async fn repos_list_full(&self) -> ServiceResult;
    async fn repos_remove(&self, params: Value) -> ServiceResult;
    async fn emergency_disable(&self) -> ServiceResult;
    async fn skill_enable(&self, params: Value) -> ServiceResult;
    async fn skill_disable(&self, params: Value) -> ServiceResult;
    async fn skill_trust(&self, params: Value) -> ServiceResult;
    async fn skill_detail(&self, params: Value) -> ServiceResult;
    async fn install_dep(&self, params: Value) -> ServiceResult;
    async fn security_status(&self) -> ServiceResult;
    async fn security_scan(&self) -> ServiceResult;
}

/// Minimal stub for `SkillsService` used only by the `Services::default()` impl.
/// The gateway provides the full implementation (`NoopSkillsService`) that
/// delegates to `moltis_skills`.
pub struct NoopSkillsStub;

#[async_trait]
impl SkillsService for NoopSkillsStub {
    ...
}

// ── Browser ─────────────────────────────────────────────────────────────────

#[async_trait]
pub trait BrowserService: Send + Sync {
    async fn request(&self, params: Value) -> ServiceResult;
    /// Initialize browser internals opportunistically after startup.
    async fn warmup(&self) {
    ...
}

pub struct NoopBrowserService;

#[async_trait]
impl BrowserService for NoopBrowserService {
    async fn request(&self, _p: Value) -> ServiceResult {
}

// ── Usage ───────────────────────────────────────────────────────────────────

#[async_trait]
pub trait UsageService: Send + Sync {
    async fn status(&self) -> ServiceResult;
    async fn cost(&self, params: Value) -> ServiceResult;
}

pub struct NoopUsageService;

#[async_trait]
impl UsageService for NoopUsageService {
    ...
}

// ── Exec Approvals ──────────────────────────────────────────────────────────

#[async_trait]
pub trait ExecApprovalService: Send + Sync {
    async fn get(&self) -> ServiceResult;
    async fn set(&self, params: Value) -> ServiceResult;
    async fn node_get(&self, params: Value) -> ServiceResult;
    async fn node_set(&self, params: Value) -> ServiceResult;
    async fn request(&self, params: Value) -> ServiceResult;
    async fn resolve(&self, params: Value) -> ServiceResult;
}

pub struct NoopExecApprovalService;

#[async_trait]
impl ExecApprovalService for NoopExecApprovalService {
    ...
}

// ── Onboarding ──────────────────────────────────────────────────────────────

#[async_trait]
pub trait OnboardingService: Send + Sync {
    async fn wizard_start(&self, params: Value) -> ServiceResult;
    async fn wizard_next(&self, params: Value) -> ServiceResult;
    async fn wizard_cancel(&self) -> ServiceResult;
    async fn wizard_status(&self) -> ServiceResult;
    async fn identity_get(&self) -> ServiceResult;
    async fn identity_update(&self, params: Value) -> ServiceResult;
    async fn identity_update_soul(&self, soul: Option<String>) -> ServiceResult;
    async fn openclaw_detect(&self) -> ServiceResult;
    async fn openclaw_scan(&self) -> ServiceResult;
    async fn openclaw_import(&self, params: Value) -> ServiceResult;
}

pub struct NoopOnboardingService;

#[async_trait]
impl OnboardingService for NoopOnboardingService {
    ...
}

// ── Update ──────────────────────────────────────────────────────────────────

#[async_trait]
pub trait UpdateService: Send + Sync {
    async fn run(&self, params: Value) -> ServiceResult;
}

pub struct NoopUpdateService;

#[async_trait]
impl UpdateService for NoopUpdateService {
    ...
}

// ── Model ───────────────────────────────────────────────────────────────────

#[async_trait]
pub trait ModelService: Send + Sync {
    /// List runtime-selectable models (unsupported models hidden).
    async fn list(&self) -> ServiceResult;
    /// List all configured models, including unsupported ones for diagnostics.
    async fn list_all(&self) -> ServiceResult;
    /// Disable a model (hide it from the list).
    async fn disable(&self, params: Value) -> ServiceResult;
    /// Enable a model (un-hide it).
    async fn enable(&self, params: Value) -> ServiceResult;
    /// Probe configured models and flag unsupported ones for this account.
    async fn detect_supported(&self, params: Value) -> ServiceResult;
    /// Test a single model by sending a probe request.
    async fn test(&self, params: Value) -> ServiceResult;
}

pub struct NoopModelService;

fn model_service_not_configured_error(operation: &'static str) -> ServiceError {
    ...
}

#[async_trait]
impl ModelService for NoopModelService {
    async fn list(&self) -> ServiceResult {

    async fn list_all(&self) -> ServiceResult {
    ...
}

    async fn disable(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn enable(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn detect_supported(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn test(&self, _params: Value) -> ServiceResult {
    ...
}
}

// ── Web Login ───────────────────────────────────────────────────────────────

#[async_trait]
pub trait WebLoginService: Send + Sync {
    async fn start(&self, params: Value) -> ServiceResult;
    async fn wait(&self, params: Value) -> ServiceResult;
}

pub struct NoopWebLoginService;

#[async_trait]
impl WebLoginService for NoopWebLoginService {
    ...
}

// ── Voicewake ───────────────────────────────────────────────────────────────

#[async_trait]
pub trait VoicewakeService: Send + Sync {
    async fn get(&self) -> ServiceResult;
    async fn set(&self, params: Value) -> ServiceResult;
    async fn wake(&self, params: Value) -> ServiceResult;
    async fn talk_mode(&self, params: Value) -> ServiceResult;
}

pub struct NoopVoicewakeService;

#[async_trait]
impl VoicewakeService for NoopVoicewakeService {
    ...
}

// ── Logs ────────────────────────────────────────────────────────────────────

#[async_trait]
pub trait LogsService: Send + Sync {
    async fn tail(&self, params: Value) -> ServiceResult;
    async fn list(&self, params: Value) -> ServiceResult;
    async fn status(&self) -> ServiceResult;
    async fn ack(&self) -> ServiceResult;
    /// Return the path to the persisted JSONL log file, if available.
    fn log_file_path(&self) -> Option<std::path::PathBuf>;
}

pub struct NoopLogsService;

#[async_trait]
impl LogsService for NoopLogsService {
    ...
}

// ── Provider Setup ──────────────────────────────────────────────────────────

#[async_trait]
pub trait ProviderSetupService: Send + Sync {
    async fn available(&self) -> ServiceResult;
    async fn save_key(&self, params: Value) -> ServiceResult;
    async fn oauth_start(&self, params: Value) -> ServiceResult;
    async fn oauth_complete(&self, params: Value) -> ServiceResult;
    async fn oauth_status(&self, params: Value) -> ServiceResult;
    async fn remove_key(&self, params: Value) -> ServiceResult;
    /// Validate provider credentials without persisting them.
    /// Returns ` {
    ...
}

pub struct NoopProviderSetupService;

#[async_trait]
impl ProviderSetupService for NoopProviderSetupService {
    async fn available(&self) -> ServiceResult {

    async fn save_key(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn oauth_start(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn oauth_complete(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn oauth_status(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn remove_key(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn validate_key(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn save_model(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn save_models(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn add_custom(&self, _p: Value) -> ServiceResult {
    ...
}
}

// ── Project ─────────────────────────────────────────────────────────────────

#[async_trait]
pub trait ProjectService: Send + Sync {
    async fn list(&self) -> ServiceResult;
    async fn get(&self, params: Value) -> ServiceResult;
    async fn upsert(&self, params: Value) -> ServiceResult;
    async fn delete(&self, params: Value) -> ServiceResult;
    async fn detect(&self, params: Value) -> ServiceResult;
    async fn complete_path(&self, params: Value) -> ServiceResult;
    async fn context(&self, params: Value) -> ServiceResult;
}

pub struct NoopProjectService;

#[async_trait]
impl ProjectService for NoopProjectService {
    ...
}

// ── Local LLM ───────────────────────────────────────────────────────────────

/// Service for managing local LLM provider (GGUF/MLX).
#[async_trait]
pub trait LocalLlmService: Send + Sync {
    /// Get system info (RAM, GPU, memory tier).
    async fn system_info(&self) -> ServiceResult;
    /// Get available models with recommendations based on memory tier.
    async fn models(&self) -> ServiceResult;
    /// Configure and load a model by ID (from registry).
    async fn configure(&self, params: Value) -> ServiceResult;
    /// Get current provider status (loading/loaded/error).
    async fn status(&self) -> ServiceResult;
    /// Search HuggingFace for models by query and backend.
    async fn search_hf(&self, params: Value) -> ServiceResult;
    /// Configure a custom model from HuggingFace repo URL.
    async fn configure_custom(&self, params: Value) -> ServiceResult;
    /// Remove a configured model by ID.
    async fn remove_model(&self, params: Value) -> ServiceResult;
}

pub struct NoopLocalLlmService;

#[async_trait]
impl LocalLlmService for NoopLocalLlmService {
    ...
}

// ── System Info ──────────────────────────────────────────────────────────────

/// Service trait for gateway-level system information.
///
/// Covers methods that read gateway state directly (connections, nodes, hooks,
/// heartbeat) rather than delegating to a domain service.
#[async_trait]
pub trait SystemInfoService: Send + Sync {
    async fn health(&self) -> ServiceResult;
    async fn status(&self) -> ServiceResult;
    async fn system_presence(&self) -> ServiceResult;
    async fn node_list(&self) -> ServiceResult;
    async fn node_describe(&self, params: Value) -> ServiceResult;
    async fn hooks_list(&self) -> ServiceResult;
    async fn heartbeat_status(&self) -> ServiceResult;
    async fn heartbeat_runs(&self, params: Value) -> ServiceResult;
}

pub struct NoopSystemInfoService;

#[async_trait]
impl SystemInfoService for NoopSystemInfoService {
    ...
}

// ── Services bundle ─────────────────────────────────────────────────────────

use std::sync::Arc;

/// Bundle of all domain service trait objects.
///
/// Shared by the gateway (RPC), GraphQL, and any other transport layer.
/// Both sides call service methods directly through this struct — no
/// string-based dispatch or RPC indirection.
pub struct Services {
    ...
}

impl Default for Services {
    fn default() -> Self {
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn noop_browser_service_lifecycle_methods() {
    ...
}

    #[tokio::test]
    async fn noop_browser_service_request_returns_error() {
    ...
}

    #[tokio::test]
    async fn browser_shutdown_with_grace_times_out() {
    ...
}

    #[test]
    fn model_service_not_configured_error_returns_expected_message() {
    ...
}
}
