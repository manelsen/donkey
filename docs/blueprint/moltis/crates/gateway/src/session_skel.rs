use std::sync::Arc;

use {
    async_trait::async_trait,
    base64::{Engine, engine::general_purpose},
    serde::Deserialize,
    serde_json::Value,
    tracing::{info, warn},
};

use {
    moltis_common::hooks::HookRegistry,
    moltis_projects::ProjectStore,
    moltis_sessions::{
        message::PersistedMessage, metadata::SqliteSessionMetadata, state_store::SessionStateStore,
        store::SessionStore,
    },
    moltis_tools::sandbox::SandboxRouter,
};

use crate::{
    agent_persona::AgentPersonaStore,
    services::{ServiceError, ServiceResult, SessionService, TtsService},
    session_types::{PatchParams, VoiceGenerateParams, VoiceTarget, parse_params},
    share_store::{
        ShareSnapshot, ShareStore, ShareVisibility, SharedImageAsset, SharedImageSet,
        SharedMapLinks, SharedMessage, SharedMessageRole,
    },
};

const SHARE_BOUNDARY_NOTICE: &str =
    "This session until here has been shared. Later messages are not included in the shared link.";
const SHARE_PREVIEW_MAX_IMAGE_WIDTH: u32 = 430;
const SHARE_PREVIEW_MAX_IMAGE_HEIGHT: u32 = 430;
const SHARE_REDACTED_VALUE: &str = "[REDACTED]";
const SESSION_PREVIEW_MAX_CHARS: usize = 200;
const UI_HISTORY_MAX_BYTES: usize = 2 * 1024 * 1024;
const UI_HISTORY_MIN_MESSAGES: usize = 120;
const UI_HISTORY_TRIM_STEP: usize = 50;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TtsStatusPayload {
    ...
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TtsConvertPayload {
    ...
}

/// Filter out empty assistant messages from history before sending to the UI.
///
/// Empty assistant messages are persisted in the session JSONL for LLM history
/// coherence (so the model sees a complete user→assistant turn), but they
/// should not be shown in the web UI or sent to channels.
fn filter_ui_history(messages: Vec<Value>) -> Vec<Value> {
    ...
}

/// Extract text content from a single message Value.
fn message_text(msg: &Value) -> Option<String> {
    ...
}

fn sanitize_tts_text(text: &str) -> String {
    ...
}

/// Truncate a string to `max` chars, appending "…" if truncated.
fn truncate_preview(s: &str, max: usize) -> String {
    ...
}

/// Build a preview by combining user and assistant messages until we
/// have enough text (target ~80 chars). Skips tool_result messages.
fn extract_preview(history: &[Value]) -> Option<String> {
    ...
}

fn trim_ui_history(mut history: Vec<Value>) -> (Vec<Value>, usize) {
    ...
}

fn value_u64(msg: &Value, key: &str) -> Option<u64> {
    ...
}

fn message_text_for_share(msg: &Value) -> Option<String> {
    ...
}

fn message_reasoning_for_share(msg: &Value) -> Option<String> {
    ...
}

fn media_filename(path: &str) -> Option<&str> {
    ...
}

fn audio_mime_type(filename: &str) -> &'static str {
    ...
}

fn image_mime_type(filename: &str) -> &'static str {
    ...
}

fn sniff_image_mime(bytes: &[u8], fallback: &str) -> String {
    ...
}

fn build_image_data_url(mime: &str, bytes: &[u8]) -> String {
    ...
}

fn parse_base64_image_data_url(data_url: &str) -> Option<(String, Vec<u8>)> {
    ...
}

async fn message_audio_data_url_for_share(
    msg: &Value,
    session_key: &str,
    store: &SessionStore,
) -> Option<String> {
    ...
}

async fn tool_result_image_for_share(
    msg: &Value,
    session_key: &str,
    store: &SessionStore,
) -> Option<SharedImageSet> {
    ...
}

fn sanitize_share_url(url: &str) -> Option<String> {
    ...
}

fn is_assignment_key_byte(byte: u8) -> bool {
    ...
}

fn is_assignment_value_delimiter(byte: u8) -> bool {
    ...
}
}

fn normalize_assignment_key(key: &str) -> String {
    ...
}

fn is_env_var_key(key: &str) -> bool {
    ...
}

fn is_sensitive_assignment_key(key: &str) -> bool {
    ...
}

fn should_redact_assignment_key(key: &str) -> bool {
    ...
}

fn starts_with_ignore_ascii_case(text: &str, start: usize, pattern: &str) -> bool {
    ...
}

fn assignment_key_bounds(text: &str, separator_idx: usize) -> Option<(usize, usize)> {
    ...
}

fn assignment_value_bounds(text: &str, separator_idx: usize, key: &str) -> Option<(usize, usize)> {
    ...
}

fn redact_assignment_values(text: &str) -> String {
    ...
}

fn find_case_insensitive(haystack: &str, needle: &str, from: usize) -> Option<usize> {
    ...
}

fn redact_bearer_tokens(text: &str) -> String {
    ...
}

fn redact_share_secret_values(text: &str) -> String {
    ...
}

fn tool_result_map_links_for_share(msg: &Value) -> Option<SharedMapLinks> {
    ...
}

fn tool_result_text_for_share(msg: &Value) -> Option<String> {
    ...
}

async fn to_shared_message(
    msg: &Value,
    session_key: &str,
    store: &SessionStore,
) -> Option<SharedMessage> {
    ...
}

/// Live session service backed by JSONL store + SQLite metadata.
pub struct LiveSessionService {
    ...
}

impl LiveSessionService {
    pub fn new(store: Arc<SessionStore>, metadata: Arc<SqliteSessionMetadata>) -> Self {

    pub fn with_sandbox_router(mut self, router: Arc<SandboxRouter>) -> Self {
    ...
}

    pub fn with_agent_persona_store(mut self, store: Arc<AgentPersonaStore>) -> Self {
    ...
}

    pub fn with_tts_service(mut self, tts: Arc<dyn TtsService>) -> Self {
    ...
}

    pub fn with_share_store(mut self, store: Arc<ShareStore>) -> Self {
    ...
}

    pub fn with_project_store(mut self, store: Arc<dyn ProjectStore>) -> Self {
    ...
}

    pub fn with_hooks(mut self, registry: Arc<HookRegistry>) -> Self {
    ...
}

    pub fn with_state_store(mut self, store: Arc<SessionStateStore>) -> Self {
    ...
}

    pub fn with_browser_service(
        mut self,
        browser: Arc<dyn crate::services::BrowserService>,
    ) -> Self {
    ...
}

    async fn default_agent_id(&self) -> String {
    ...
}

    async fn resolve_agent_id_for_entry(
        &self,
        entry: &moltis_sessions::metadata::SessionEntry,
        patch_if_invalid: bool,
    ) -> String {
    ...
}

    async fn ensure_entry_agent_id(
        &self,
        key: &str,
        inherit_from_key: Option<&str>,
    ) -> Option<moltis_sessions::metadata::SessionEntry> {
    ...
}
}

#[async_trait]
impl SessionService for LiveSessionService {
    async fn list(&self) -> ServiceResult {

    async fn preview(&self, params: Value) -> ServiceResult {
    ...
}

    async fn resolve(&self, params: Value) -> ServiceResult {
    ...
}

    async fn patch(&self, params: Value) -> ServiceResult {
    ...
}

    async fn voice_generate(&self, params: Value) -> ServiceResult {
    ...
}

    async fn share_create(&self, params: Value) -> ServiceResult {
    ...
}

    async fn share_list(&self, params: Value) -> ServiceResult {
    ...
}

    async fn share_revoke(&self, params: Value) -> ServiceResult {
    ...
}

    async fn reset(&self, params: Value) -> ServiceResult {
    ...
}

    async fn delete(&self, params: Value) -> ServiceResult {
    ...
}

    async fn compact(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn fork(&self, params: Value) -> ServiceResult {
    ...
}

    async fn branches(&self, params: Value) -> ServiceResult {
    ...
}

    async fn search(&self, params: Value) -> ServiceResult {
    ...
}

    async fn mark_seen(&self, key: &str) {
    ...
}

    async fn clear_all(&self) -> ServiceResult {
    ...
}

    async fn run_detail(&self, params: Value) -> ServiceResult {
    ...
}
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn filter_ui_history_removes_whitespace_only_assistant() {
    ...
}

    #[test]
    fn filter_ui_history_keeps_non_empty_assistant() {
    ...
}

    #[test]
    fn filter_ui_history_keeps_non_assistant_roles() {
    ...
}

    #[test]
    fn filter_ui_history_keeps_reasoning_only_assistant() {
    ...
}

    #[test]
    fn trim_ui_history_drops_oldest_messages_when_payload_is_too_large() {
    ...
}

    // --- Preview extraction tests ---

    #[test]
    fn message_text_from_string_content() {
    ...
}

    #[test]
    fn message_text_from_content_blocks() {
    ...
}

    #[test]
    fn message_text_empty_content() {
    ...
}

    #[test]
    fn message_text_no_content_field() {
    ...
}

    #[test]
    fn truncate_preview_short_string() {
    ...
}

    #[test]
    fn truncate_preview_long_string() {
    ...
}

    #[test]
    fn extract_preview_single_short_message() {
    ...
}

    #[test]
    fn extract_preview_combines_messages_until_target() {
    ...
}

    #[test]
    fn extract_preview_skips_system_and_tool_messages() {
    ...
}

    #[test]
    fn extract_preview_empty_history() {
    ...
}

    #[test]
    fn extract_preview_only_system_messages() {
    ...
}

    #[test]
    fn extract_preview_truncates_at_max() {
    ...
}

    #[test]
    fn media_filename_extracts_last_segment() {
    ...
}

    #[test]
    fn audio_mime_type_maps_known_extensions() {
    ...
}

    #[test]
    fn image_mime_type_maps_known_extensions() {
    ...
}

    #[test]
    fn sanitize_share_url_rejects_unsafe_schemes() {
    ...
}

    #[tokio::test]
    async fn message_audio_data_url_for_share_reads_media_file() {
    ...
}

    #[tokio::test]
    async fn to_shared_message_skips_system_and_notice_roles() {
    ...
}

    #[tokio::test]
    async fn to_shared_message_includes_user_audio_without_text() {
    ...
}

    #[tokio::test]
    async fn to_shared_message_includes_assistant_audio() {
    ...
}

    #[tokio::test]
    async fn to_shared_message_includes_assistant_reasoning_without_text() {
    ...
}

    #[tokio::test]
    async fn to_shared_message_includes_tool_result_screenshot_and_map_links() {
    ...
}

    #[test]
    fn tool_result_text_for_share_preserves_full_stdout() {
    ...
}

    #[test]
    fn redact_share_secret_values_masks_env_vars_and_api_tokens() {
    ...
}

    #[test]
    fn tool_result_text_for_share_redacts_sensitive_values() {
    ...
}

    #[tokio::test]
    async fn to_shared_message_includes_exec_command_for_tool_result() {
    ...
}

    #[tokio::test]
    async fn to_shared_message_redacts_exec_command_and_output_secrets() {
    ...
}

    struct MockTtsService {
    ...
}

    impl MockTtsService {
        fn new(status_payload: Value, convert_payload: Option<Value>) -> Self {

        fn with_convert_error(status_payload: Value, error: &str) -> Self {
    ...
}
    }

    #[async_trait]
    impl TtsService for MockTtsService {
        async fn status(&self) -> ServiceResult {

        async fn providers(&self) -> ServiceResult {
    ...
}

        async fn enable(&self, _params: Value) -> ServiceResult {
    ...
}

        async fn disable(&self) -> ServiceResult {
    ...
}

        async fn convert(&self, _params: Value) -> ServiceResult {
    ...
}

        async fn set_provider(&self, _params: Value) -> ServiceResult {
    ...
}
    }

    #[tokio::test]
    async fn voice_generate_reuses_existing_audio_without_tts_convert() {
    ...
}

    #[tokio::test]
    async fn voice_generate_creates_and_persists_audio() {
    ...
}

    #[tokio::test]
    async fn voice_generate_rejects_non_assistant_target() {
    ...
}

    #[tokio::test]
    async fn voice_generate_prefers_run_id_over_non_assistant_message_index() {
    ...
}

    // --- Browser service integration tests ---

    use std::sync::atomic::{AtomicU32, Ordering};

    /// Mock browser service that tracks lifecycle method calls.
    struct MockBrowserService {
    ...
}

    impl MockBrowserService {
        fn new() -> Self {

        fn close_all_count(&self) -> u32 {
    ...
}
    }

    #[async_trait]
    impl crate::services::BrowserService for MockBrowserService {
        async fn request(&self, _p: Value) -> ServiceResult {

        async fn close_all(&self) {
    ...
}
    }

    async fn sqlite_pool() -> sqlx::SqlitePool {
    ...
}

    #[tokio::test]
    async fn with_browser_service_builder() {
    ...
}

    #[tokio::test]
    async fn clear_all_calls_browser_close_all() {
    ...
}

    #[tokio::test]
    async fn clear_all_without_browser_service() {
    ...
}

    #[tokio::test]
    async fn patch_sandbox_toggle_appends_system_notification() {
    ...
}

    #[tokio::test]
    async fn patch_sandbox_no_change_skips_notification() {
    ...
}

    #[tokio::test]
    async fn patch_sandbox_null_clears_override_with_notification() {
    ...
}
}
