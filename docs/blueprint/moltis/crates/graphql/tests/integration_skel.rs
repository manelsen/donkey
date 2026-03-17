//! Integration tests for the moltis-graphql crate.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use {
    async_graphql::Request,
    moltis_service_traits::{ServiceResult, Services},
    serde_json::{Value, json},
    tokio::{
        sync::broadcast,
        time::{Duration, timeout},
    },
    tokio_stream::StreamExt,
};

// ── Mock dispatch ────────────────────────────────────────────────────────────

/// Central mock that records calls and returns preset responses.
/// Used by all mock service implementations below.
struct MockDispatch {
    ...
}

impl MockDispatch {
    fn new() -> Arc<Self> {

    fn set_response(&self, method: &str, response: Value) {
    ...
}

    fn call(&self, method: &str, params: Value) -> ServiceResult {
    ...
}

    fn call_count(&self) -> usize {
    ...
}

    fn last_call(&self) -> Option<(String, Value)> {
    ...
}
}

// ── Mock service implementations ─────────────────────────────────────────────
//
// Each mock implements a service trait by delegating to MockDispatch using
// the same method name strings the old ServiceCaller used. This preserves
// test compatibility with minimal changes.

macro_rules! mock_svc_struct {
    ($name:ident) => {
        struct $name(Arc<MockDispatch>);
    };
}

mock_svc_struct!(MockAgent);
mock_svc_struct!(MockSession);
mock_svc_struct!(MockChannel);
mock_svc_struct!(MockConfig);
mock_svc_struct!(MockCron);
mock_svc_struct!(MockChat);
mock_svc_struct!(MockTts);
mock_svc_struct!(MockStt);
mock_svc_struct!(MockSkills);
mock_svc_struct!(MockMcp);
mock_svc_struct!(MockBrowser);
mock_svc_struct!(MockUsage);
mock_svc_struct!(MockExecApproval);
mock_svc_struct!(MockOnboarding);
mock_svc_struct!(MockUpdate);
mock_svc_struct!(MockModel);
mock_svc_struct!(MockWebLogin);
mock_svc_struct!(MockVoicewake);
mock_svc_struct!(MockLogs);
mock_svc_struct!(MockProviderSetup);
mock_svc_struct!(MockProject);
mock_svc_struct!(MockLocalLlm);
mock_svc_struct!(MockSystemInfo);

#[async_trait::async_trait]
impl moltis_service_traits::AgentService for MockAgent {
    async fn run(&self, params: Value) -> ServiceResult {

    async fn run_wait(&self, params: Value) -> ServiceResult {
    ...
}

    async fn identity_get(&self) -> ServiceResult {
    ...
}

    async fn list(&self) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::SessionService for MockSession {
    async fn list(&self) -> ServiceResult {

    async fn preview(&self, p: Value) -> ServiceResult {
    ...
}

    async fn resolve(&self, p: Value) -> ServiceResult {
    ...
}

    async fn patch(&self, p: Value) -> ServiceResult {
    ...
}

    async fn voice_generate(&self, p: Value) -> ServiceResult {
    ...
}

    async fn share_create(&self, p: Value) -> ServiceResult {
    ...
}

    async fn share_list(&self, p: Value) -> ServiceResult {
    ...
}

    async fn share_revoke(&self, p: Value) -> ServiceResult {
    ...
}

    async fn reset(&self, p: Value) -> ServiceResult {
    ...
}

    async fn delete(&self, p: Value) -> ServiceResult {
    ...
}

    async fn compact(&self, p: Value) -> ServiceResult {
    ...
}

    async fn search(&self, p: Value) -> ServiceResult {
    ...
}

    async fn fork(&self, p: Value) -> ServiceResult {
    ...
}

    async fn branches(&self, p: Value) -> ServiceResult {
    ...
}

    async fn run_detail(&self, p: Value) -> ServiceResult {
    ...
}

    async fn clear_all(&self) -> ServiceResult {
    ...
}

    async fn mark_seen(&self, _key: &str) {
    ...
}

#[async_trait::async_trait]
impl moltis_service_traits::ChannelService for MockChannel {
    async fn status(&self) -> ServiceResult {

    async fn logout(&self, p: Value) -> ServiceResult {
    ...
}

    async fn send(&self, p: Value) -> ServiceResult {
    ...
}

    async fn add(&self, p: Value) -> ServiceResult {
    ...
}

    async fn remove(&self, p: Value) -> ServiceResult {
    ...
}

    async fn update(&self, p: Value) -> ServiceResult {
    ...
}

    async fn senders_list(&self, p: Value) -> ServiceResult {
    ...
}

    async fn sender_approve(&self, p: Value) -> ServiceResult {
    ...
}

    async fn sender_deny(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::ConfigService for MockConfig {
    async fn get(&self, p: Value) -> ServiceResult {

    async fn set(&self, p: Value) -> ServiceResult {
    ...
}

    async fn apply(&self, p: Value) -> ServiceResult {
    ...
}

    async fn patch(&self, p: Value) -> ServiceResult {
    ...
}

    async fn schema(&self) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::CronService for MockCron {
    async fn list(&self) -> ServiceResult {

    async fn status(&self) -> ServiceResult {
    ...
}

    async fn add(&self, p: Value) -> ServiceResult {
    ...
}

    async fn update(&self, p: Value) -> ServiceResult {
    ...
}

    async fn remove(&self, p: Value) -> ServiceResult {
    ...
}

    async fn run(&self, p: Value) -> ServiceResult {
    ...
}

    async fn runs(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::ChatService for MockChat {
    async fn send(&self, p: Value) -> ServiceResult {

    async fn abort(&self, p: Value) -> ServiceResult {
    ...
}

    async fn cancel_queued(&self, p: Value) -> ServiceResult {
    ...
}

    async fn history(&self, p: Value) -> ServiceResult {
    ...
}

    async fn inject(&self, p: Value) -> ServiceResult {
    ...
}

    async fn clear(&self, p: Value) -> ServiceResult {
    ...
}

    async fn compact(&self, p: Value) -> ServiceResult {
    ...
}

    async fn context(&self, p: Value) -> ServiceResult {
    ...
}

    async fn raw_prompt(&self, p: Value) -> ServiceResult {
    ...
}

    async fn full_context(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::TtsService for MockTts {
    async fn status(&self) -> ServiceResult {

    async fn providers(&self) -> ServiceResult {
    ...
}

    async fn enable(&self, p: Value) -> ServiceResult {
    ...
}

    async fn disable(&self) -> ServiceResult {
    ...
}

    async fn convert(&self, p: Value) -> ServiceResult {
    ...
}

    async fn set_provider(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::SttService for MockStt {
    async fn status(&self) -> ServiceResult {

    async fn providers(&self) -> ServiceResult {
    ...
}

    async fn transcribe(&self, p: Value) -> ServiceResult {
    ...
}

    async fn transcribe_bytes(
        &self,
        _audio: bytes::Bytes,
        _format: &str,
        _provider: Option<&str>,
        _language: Option<&str>,
        _prompt: Option<&str>,
    ) -> ServiceResult {
    ...
}

    async fn set_provider(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::SkillsService for MockSkills {
    async fn status(&self) -> ServiceResult {

    async fn bins(&self) -> ServiceResult {
    ...
}

    async fn install(&self, p: Value) -> ServiceResult {
    ...
}

    async fn update(&self, p: Value) -> ServiceResult {
    ...
}

    async fn list(&self) -> ServiceResult {
    ...
}

    async fn remove(&self, p: Value) -> ServiceResult {
    ...
}

    async fn repos_list(&self) -> ServiceResult {
    ...
}

    async fn repos_list_full(&self) -> ServiceResult {
    ...
}

    async fn repos_remove(&self, p: Value) -> ServiceResult {
    ...
}

    async fn emergency_disable(&self) -> ServiceResult {
    ...
}

    async fn skill_enable(&self, p: Value) -> ServiceResult {
    ...
}

    async fn skill_disable(&self, p: Value) -> ServiceResult {
    ...
}

    async fn skill_trust(&self, p: Value) -> ServiceResult {
    ...
}

    async fn skill_detail(&self, p: Value) -> ServiceResult {
    ...
}

    async fn install_dep(&self, p: Value) -> ServiceResult {
    ...
}

    async fn security_status(&self) -> ServiceResult {
    ...
}

    async fn security_scan(&self) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::McpService for MockMcp {
    async fn list(&self) -> ServiceResult {

    async fn add(&self, p: Value) -> ServiceResult {
    ...
}

    async fn remove(&self, p: Value) -> ServiceResult {
    ...
}

    async fn enable(&self, p: Value) -> ServiceResult {
    ...
}

    async fn disable(&self, p: Value) -> ServiceResult {
    ...
}

    async fn status(&self, p: Value) -> ServiceResult {
    ...
}

    async fn tools(&self, p: Value) -> ServiceResult {
    ...
}

    async fn restart(&self, p: Value) -> ServiceResult {
    ...
}

    async fn update(&self, p: Value) -> ServiceResult {
    ...
}

    async fn reauth(&self, p: Value) -> ServiceResult {
    ...
}

    async fn oauth_start(&self, p: Value) -> ServiceResult {
    ...
}

    async fn oauth_complete(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::BrowserService for MockBrowser {
    async fn request(&self, p: Value) -> ServiceResult {
}

#[async_trait::async_trait]
impl moltis_service_traits::UsageService for MockUsage {
    async fn status(&self) -> ServiceResult {

    async fn cost(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::ExecApprovalService for MockExecApproval {
    async fn get(&self) -> ServiceResult {

    async fn set(&self, p: Value) -> ServiceResult {
    ...
}

    async fn node_get(&self, p: Value) -> ServiceResult {
    ...
}

    async fn node_set(&self, p: Value) -> ServiceResult {
    ...
}

    async fn request(&self, p: Value) -> ServiceResult {
    ...
}

    async fn resolve(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::OnboardingService for MockOnboarding {
    async fn wizard_start(&self, p: Value) -> ServiceResult {

    async fn wizard_next(&self, p: Value) -> ServiceResult {
    ...
}

    async fn wizard_cancel(&self) -> ServiceResult {
    ...
}

    async fn wizard_status(&self) -> ServiceResult {
    ...
}

    async fn identity_get(&self) -> ServiceResult {
    ...
}

    async fn identity_update(&self, p: Value) -> ServiceResult {
    ...
}

    async fn identity_update_soul(&self, soul: Option<String>) -> ServiceResult {
    ...
}

    async fn openclaw_detect(&self) -> ServiceResult {
    ...
}

    async fn openclaw_scan(&self) -> ServiceResult {
    ...
}

    async fn openclaw_import(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::UpdateService for MockUpdate {
    async fn run(&self, p: Value) -> ServiceResult {
}

#[async_trait::async_trait]
impl moltis_service_traits::ModelService for MockModel {
    async fn list(&self) -> ServiceResult {

    async fn list_all(&self) -> ServiceResult {
    ...
}

    async fn disable(&self, p: Value) -> ServiceResult {
    ...
}

    async fn enable(&self, p: Value) -> ServiceResult {
    ...
}

    async fn detect_supported(&self, p: Value) -> ServiceResult {
    ...
}

    async fn test(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::WebLoginService for MockWebLogin {
    async fn start(&self, p: Value) -> ServiceResult {

    async fn wait(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::VoicewakeService for MockVoicewake {
    async fn get(&self) -> ServiceResult {

    async fn set(&self, p: Value) -> ServiceResult {
    ...
}

    async fn wake(&self, p: Value) -> ServiceResult {
    ...
}

    async fn talk_mode(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::LogsService for MockLogs {
    async fn tail(&self, p: Value) -> ServiceResult {

    async fn list(&self, p: Value) -> ServiceResult {
    ...
}

    async fn status(&self) -> ServiceResult {
    ...
}

    async fn ack(&self) -> ServiceResult {
    ...
}

    fn log_file_path(&self) -> Option<std::path::PathBuf> {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::ProviderSetupService for MockProviderSetup {
    async fn available(&self) -> ServiceResult {

    async fn save_key(&self, p: Value) -> ServiceResult {
    ...
}

    async fn oauth_start(&self, p: Value) -> ServiceResult {
    ...
}

    async fn oauth_complete(&self, p: Value) -> ServiceResult {
    ...
}

    async fn oauth_status(&self, p: Value) -> ServiceResult {
    ...
}

    async fn remove_key(&self, p: Value) -> ServiceResult {
    ...
}

    async fn validate_key(&self, p: Value) -> ServiceResult {
    ...
}

    async fn save_model(&self, p: Value) -> ServiceResult {
    ...
}

    async fn save_models(&self, p: Value) -> ServiceResult {
    ...
}

    async fn add_custom(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::ProjectService for MockProject {
    async fn list(&self) -> ServiceResult {

    async fn get(&self, p: Value) -> ServiceResult {
    ...
}

    async fn upsert(&self, p: Value) -> ServiceResult {
    ...
}

    async fn delete(&self, p: Value) -> ServiceResult {
    ...
}

    async fn detect(&self, p: Value) -> ServiceResult {
    ...
}

    async fn complete_path(&self, p: Value) -> ServiceResult {
    ...
}

    async fn context(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::LocalLlmService for MockLocalLlm {
    async fn system_info(&self) -> ServiceResult {

    async fn models(&self) -> ServiceResult {
    ...
}

    async fn configure(&self, p: Value) -> ServiceResult {
    ...
}

    async fn status(&self) -> ServiceResult {
    ...
}

    async fn search_hf(&self, p: Value) -> ServiceResult {
    ...
}

    async fn configure_custom(&self, p: Value) -> ServiceResult {
    ...
}

    async fn remove_model(&self, p: Value) -> ServiceResult {
    ...
}
}

#[async_trait::async_trait]
impl moltis_service_traits::SystemInfoService for MockSystemInfo {
    async fn health(&self) -> ServiceResult {

    async fn status(&self) -> ServiceResult {
    ...
}

    async fn system_presence(&self) -> ServiceResult {
    ...
}

    async fn node_list(&self) -> ServiceResult {
    ...
}

    async fn node_describe(&self, p: Value) -> ServiceResult {
    ...
}

    async fn hooks_list(&self) -> ServiceResult {
    ...
}

    async fn heartbeat_status(&self) -> ServiceResult {
    ...
}

    async fn heartbeat_runs(&self, p: Value) -> ServiceResult {
    ...
}
}

// ── Test helpers ─────────────────────────────────────────────────────────────

fn build_mock_services(mock: &Arc<MockDispatch>) -> Arc<Services> {
    ...
}

fn build_test_schema(
    mock: Arc<MockDispatch>,
) -> (
    moltis_graphql::MoltisSchema,
    broadcast::Sender<(String, Value)>,
) {
    ...
}

// ── Schema introspection ────────────────────────────────────────────────────

#[tokio::test]
async fn introspection_returns_types() {
    ...
}

#[tokio::test]
async fn introspection_lists_query_fields() {
    ...
}

// ── Query resolvers ─────────────────────────────────────────────────────────

#[tokio::test]
async fn health_query_returns_data() {
    ...
}

#[tokio::test]
async fn status_query_returns_data() {
    ...
}

#[tokio::test]
async fn cron_list_query() {
    ...
}

#[tokio::test]
async fn sessions_list_query() {
    ...
}

#[tokio::test]
async fn system_presence_query_returns_typed_shape() {
    ...
}

#[tokio::test]
async fn logs_status_query_returns_typed_shape() {
    ...
}

// ── Mutation resolvers ──────────────────────────────────────────────────────

#[tokio::test]
async fn config_set_mutation() {
    ...
}

#[tokio::test]
async fn chat_send_mutation() {
    ...
}

#[tokio::test]
async fn agents_update_identity_mutation_returns_ok_on_success() {
    ...
}

#[tokio::test]
async fn agents_update_identity_accepts_json_string_payload() {
    ...
}

#[tokio::test]
async fn providers_oauth_start_mutation_returns_typed_shape() {
    ...
}

#[tokio::test]
async fn cron_add_mutation() {
    ...
}

// ── Error propagation ───────────────────────────────────────────────────────

#[tokio::test]
async fn service_error_becomes_graphql_error() {
    ...
}

// ── Namespace nesting ───────────────────────────────────────────────────────

#[tokio::test]
async fn nested_query_namespaces() {
    ...
}

// ── Subscription types exist ────────────────────────────────────────────────

#[tokio::test]
async fn subscription_types_exist_in_schema() {
    ...
}

// ── Multiple queries in one request ─────────────────────────────────────────

#[tokio::test]
async fn multiple_root_queries() {
    ...
}

#[tokio::test]
async fn parse_error_becomes_graphql_error() {
    ...
}

#[test]
fn json_wrapper_traits_and_generic_event_conversion() {
    ...
}

// ── Subscription event streams ──────────────────────────────────────────────

#[tokio::test]
async fn subscription_event_stream_variants_emit_payloads() {
    ...
}

#[tokio::test]
async fn chat_event_subscription_filters_by_session_key() {
    ...
}

#[tokio::test]
async fn tick_approval_and_all_events_subscriptions_emit() {
    ...
}
