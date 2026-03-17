//! Trait interfaces for domain services the gateway delegates to.
//! Each trait has a `Noop` implementation that returns empty/default responses,
//! allowing the gateway to run standalone before domain crates are wired in.
//!
//! Pure trait definitions and simple noop implementations live in `moltis-service-traits`.
//! This module re-exports everything from that crate and adds gateway-specific implementations.

// Re-export all trait definitions and simple noops from service-traits.
pub use moltis_service_traits::*;

use {
    async_trait::async_trait,
    serde_json::Value,
    std::{collections::HashSet, path::Path, sync::Arc},
};

fn security_audit(event: &str, details: Value) {
    ...
}

async fn command_available(command: &str) -> bool {
    ...
}

async fn run_mcp_scan(installed_dir: &Path) -> anyhow::Result<Value> {
    ...
}

/// Returns `true` for discovered skill names that are protected and cannot be
/// deleted from the UI (e.g. built-in template/tmux skills).
pub fn is_protected_discovered_skill(name: &str) -> bool {
    ...
}

fn commit_url_for_source(source: &str, sha: &str) -> Option<String> {
    ...
}

fn license_url_for_source(source: &str, license: Option<&str>) -> Option<String> {
    ...
}

fn local_repo_head_timestamp_ms(repo_dir: &Path) -> Option<u64> {
    ...
}

fn commit_age_days(commit_ts_ms: Option<u64>) -> Option<u64> {
    ...
}

fn risky_install_pattern(command: &str) -> Option<&'static str> {
    ...
}

/// Convert markdown to sanitized HTML using pulldown-cmark.
pub(crate) fn markdown_to_html(md: &str) -> String {
    ...
}

// ── Skills (Noop — complex impl that depends on gateway-specific crates) ────

pub struct NoopSkillsService;

#[async_trait]
impl SkillsService for NoopSkillsService {
    async fn status(&self) -> ServiceResult {
    ...
}

    async fn bins(&self) -> ServiceResult {
    ...
}

    async fn install(&self, params: Value) -> ServiceResult {
    ...
}

    async fn update(&self, _p: Value) -> ServiceResult {
    ...
}

    async fn list(&self) -> ServiceResult {
    ...
}

    async fn remove(&self, params: Value) -> ServiceResult {
    ...
}

    async fn repos_list(&self) -> ServiceResult {
    ...
}

    async fn repos_list_full(&self) -> ServiceResult {
    ...
}

    async fn repos_remove(&self, params: Value) -> ServiceResult {
    ...
}

    async fn emergency_disable(&self) -> ServiceResult {
    ...
}

    async fn skill_enable(&self, params: Value) -> ServiceResult {
    ...
}

    async fn skill_disable(&self, params: Value) -> ServiceResult {
    ...
}

    async fn skill_trust(&self, params: Value) -> ServiceResult {
    ...
}

    async fn skill_detail(&self, params: Value) -> ServiceResult {
    ...
}

    async fn install_dep(&self, params: Value) -> ServiceResult {
    ...
}

    async fn security_status(&self) -> ServiceResult {
    ...
}

    async fn security_scan(&self) -> ServiceResult {
    ...
}
}

fn local_repo_head_sha(repo_dir: &Path) -> Option<String> {
    ...
}

fn detect_and_mark_repo_drift(
    manifest: &mut moltis_skills::types::SkillsManifest,
    install_dir: &Path,
) -> (bool, HashSet<String>) {
    ...
}

/// Delete a personal or project skill directory to disable it.
fn delete_discovered_skill(source_type: &str, params: &Value) -> ServiceResult {
    ...
}

/// Load skill detail for a personal or project skill by name.
fn skill_detail_discovered(source_type: &str, skill_name: &str) -> ServiceResult {
    ...
}

fn toggle_skill(params: &Value, enabled: bool) -> ServiceResult {
    ...
}

fn set_skill_trusted(params: &Value, trusted: bool) -> ServiceResult {
    ...
}

// ── Browser (Real implementation — depends on moltis-browser) ───────────────

/// Real browser service using BrowserManager.
pub struct RealBrowserService {
    ...
}

impl RealBrowserService {
    pub fn new(config: &moltis_config::schema::BrowserConfig, container_prefix: String) -> Self {

    pub fn from_config(
        config: &moltis_config::schema::MoltisConfig,
        container_prefix: String,
    ) -> Option<Self> {
    ...
}

    async fn manager(&self) -> Arc<moltis_browser::BrowserManager> {
    ...
}

    fn manager_if_initialized(&self) -> Option<Arc<moltis_browser::BrowserManager>> {
    ...
}
}

#[async_trait]
impl BrowserService for RealBrowserService {
    async fn request(&self, params: Value) -> ServiceResult {

    async fn warmup(&self) {
    ...
}

    async fn cleanup_idle(&self) {
    ...
}

    async fn shutdown(&self) {
    ...
}

    async fn close_all(&self) {
    ...
}
}

// ── Bundled services ────────────────────────────────────────────────────────

/// All domain services the gateway delegates to.
pub struct GatewayServices {
    ...
}

impl GatewayServices {
    pub fn with_chat(mut self, chat: Arc<dyn ChatService>) -> Self {

    pub fn with_model(mut self, model: Arc<dyn ModelService>) -> Self {
    ...
}

    pub fn with_cron(mut self, cron: Arc<dyn CronService>) -> Self {
    ...
}

    pub fn with_provider_setup(mut self, ps: Arc<dyn ProviderSetupService>) -> Self {
    ...
}

    pub fn with_channel_registry(
        mut self,
        registry: Arc<moltis_channels::ChannelRegistry>,
    ) -> Self {
    ...
}

    pub fn with_channel_outbound(
        mut self,
        outbound: Arc<dyn moltis_channels::ChannelOutbound>,
    ) -> Self {
    ...
}

    pub fn with_channel_stream_outbound(
        mut self,
        outbound: Arc<dyn moltis_channels::ChannelStreamOutbound>,
    ) -> Self {
    ...
}

    pub fn channel_outbound_arc(&self) -> Option<Arc<dyn moltis_channels::ChannelOutbound>> {
    ...
}

    pub fn channel_stream_outbound_arc(
        &self,
    ) -> Option<Arc<dyn moltis_channels::ChannelStreamOutbound>> {
    ...
}

    /// Create a service bundle with all noop implementations.
    pub fn noop() -> Self {
    ...
}

    pub fn with_local_llm(mut self, local_llm: Arc<dyn LocalLlmService>) -> Self {
    ...
}

    pub fn with_network_audit(
        mut self,
        svc: Arc<dyn crate::network_audit::NetworkAuditService>,
    ) -> Self {
    ...
}

    pub fn with_onboarding(mut self, onboarding: Arc<dyn OnboardingService>) -> Self {
    ...
}

    pub fn with_project(mut self, project: Arc<dyn ProjectService>) -> Self {
    ...
}

    pub fn with_session_metadata(
        mut self,
        meta: Arc<moltis_sessions::metadata::SqliteSessionMetadata>,
    ) -> Self {
    ...
}

    pub fn with_session_store(mut self, store: Arc<moltis_sessions::store::SessionStore>) -> Self {
    ...
}

    pub fn with_session_share_store(mut self, store: Arc<crate::share_store::ShareStore>) -> Self {
    ...
}

    pub fn with_agent_persona_store(
        mut self,
        store: Arc<crate::agent_persona::AgentPersonaStore>,
    ) -> Self {
    ...
}

    pub fn with_agents_config(
        mut self,
        agents_config: Arc<tokio::sync::RwLock<moltis_config::AgentsConfig>>,
    ) -> Self {
    ...
}

    pub fn with_tts(mut self, tts: Arc<dyn TtsService>) -> Self {
    ...
}

    pub fn with_stt(mut self, stt: Arc<dyn SttService>) -> Self {
    ...
}

    /// Create a [`Services`] bundle for sharing with the GraphQL schema.
    ///
    /// Clones all service `Arc`s (cheap pointer bumps) into the shared bundle.
    /// The `system_info` service is provided separately because it needs the
    /// fully-constructed `GatewayState` which isn't available during
    /// `GatewayServices` construction.
    pub fn to_services(&self, system_info: Arc<dyn SystemInfoService>) -> Arc<Services> {
    ...
}
}

#[cfg(test)]
mod tests {

    #[test]
    fn risky_install_pattern_allows_plain_package_install() {
    ...
}
}
