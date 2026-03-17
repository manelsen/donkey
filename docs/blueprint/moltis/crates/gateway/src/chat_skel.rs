//! Chat execution engine — re-exported from [`moltis_chat`] with the gateway
//! runtime adapter.

pub use moltis_chat::*;

use std::sync::Arc;

use {async_trait::async_trait, serde_json::Value};

use {moltis_channels::ChannelReplyTarget, moltis_tools::sandbox::SandboxRouter};

use crate::state::GatewayState;

// ── GatewayChatRuntime ──────────────────────────────────────────────────────

/// Adapts [`GatewayState`] to the [`ChatRuntime`] trait expected by
/// `moltis-chat`.
pub struct GatewayChatRuntime {
    ...
}

impl GatewayChatRuntime {
    pub fn from_state(state: Arc<GatewayState>) -> Arc<dyn ChatRuntime> {
}

#[async_trait]
impl ChatRuntime for GatewayChatRuntime {
    // ── Broadcasting ────────────────────────────────────────────────────────

    async fn broadcast(&self, topic: &str, payload: Value) {

    // ── Channel reply queue ─────────────────────────────────────────────────

    async fn push_channel_reply(&self, session_key: &str, target: ChannelReplyTarget) {
    ...
}

    async fn drain_channel_replies(&self, session_key: &str) -> Vec<ChannelReplyTarget> {
    ...
}

    async fn peek_channel_replies(&self, session_key: &str) -> Vec<ChannelReplyTarget> {
    ...
}

    // ── Channel status log ──────────────────────────────────────────────────

    async fn push_channel_status_log(&self, session_key: &str, message: String) {
    ...
}

    async fn drain_channel_status_log(&self, session_key: &str) -> Vec<String> {
    ...
}

    // ── Run error tracking ──────────────────────────────────────────────────

    async fn set_run_error(&self, run_id: &str, error: String) {
    ...
}

    // ── Connection → session/project mapping ────────────────────────────────

    async fn active_session_key(&self, conn_id: &str) -> Option<String> {
    ...
}

    async fn active_project_id(&self, conn_id: &str) -> Option<String> {
    ...
}

    // ── Immutable accessors ─────────────────────────────────────────────────

    fn hostname(&self) -> &str {
    ...
}

    fn sandbox_router(&self) -> Option<&Arc<SandboxRouter>> {
    ...
}

    fn memory_manager(&self) -> Option<&Arc<moltis_memory::manager::MemoryManager>> {
    ...
}

    // ── Cached location ─────────────────────────────────────────────────────

    async fn cached_location(&self) -> Option<moltis_config::GeoLocation> {
    ...
}

    // ── TTS overrides ───────────────────────────────────────────────────────

    async fn tts_overrides(
        &self,
        session_key: &str,
        channel_key: &str,
    ) -> (Option<TtsOverride>, Option<TtsOverride>) {
    ...
}

    // ── Services ────────────────────────────────────────────────────────────

    fn channel_outbound(&self) -> Option<Arc<dyn moltis_channels::ChannelOutbound>> {
    ...
}

    fn channel_stream_outbound(&self) -> Option<Arc<dyn moltis_channels::ChannelStreamOutbound>> {
    ...
}

    fn tts_service(&self) -> &dyn moltis_service_traits::TtsService {
    ...
}

    fn project_service(&self) -> &dyn moltis_service_traits::ProjectService {
    ...
}

    fn mcp_service(&self) -> &dyn moltis_service_traits::McpService {
    ...
}

    async fn chat_service(&self) -> Arc<dyn moltis_service_traits::ChatService> {
    ...
}

    async fn last_run_error(&self, run_id: &str) -> Option<String> {
    ...
}

    // ── Push notifications ──────────────────────────────────────────────────

    async fn send_push_notification(
        &self,
        title: &str,
        body: &str,
        url: Option<&str>,
        session_key: Option<&str>,
    ) -> error::Result<usize> {
    ...
}

    // ── Local LLM ───────────────────────────────────────────────────────────

    async fn ensure_local_model_cached(&self, model_id: &str) -> error::Result<bool> {
    ...
}

    // ── Remote nodes ────────────────────────────────────────────────────────

    async fn connected_nodes(&self) -> Vec<runtime::ConnectedNodeSummary> {
    ...
}
}
