//! GraphQL mutation resolvers, organized by service namespace.
//!
//! Resolvers call domain services directly through the `Services` bundle —
//! no RPC string-based dispatch or `ServiceCaller` indirection.

use async_graphql::{Context, Object, Result};

use crate::{
    error::{from_service, from_service_json, gql_err, parse_err},
    scalars::Json,
    services,
    types::{
        BoolResult, McpOAuthStartResult, ModelTestResult, ProviderOAuthStartResult,
        SessionShareResult, TranscriptionResult, TtsConvertResult,
    },
};

/// Root mutation type composing all namespace mutations.
#[derive(Default)]
pub struct MutationRoot;

#[Object]
impl MutationRoot {
    async fn system(&self) -> SystemMutation {

    async fn node(&self) -> NodeMutation {
    ...
}

    async fn device(&self) -> DeviceMutation {
    ...
}

    async fn chat(&self) -> ChatMutation {
    ...
}

    async fn sessions(&self) -> SessionMutation {
    ...
}

    async fn channels(&self) -> ChannelMutation {
    ...
}

    async fn config(&self) -> ConfigMutation {
    ...
}

    async fn cron(&self) -> CronMutation {
    ...
}

    async fn heartbeat(&self) -> HeartbeatMutation {
    ...
}

    async fn tts(&self) -> TtsMutation {
    ...
}

    async fn stt(&self) -> SttMutation {
    ...
}

    async fn voice(&self) -> VoiceMutation {
    ...
}

    async fn skills(&self) -> SkillsMutation {
    ...
}

    async fn models(&self) -> ModelMutation {
    ...
}

    async fn providers(&self) -> ProviderMutation {
    ...
}

    async fn mcp(&self) -> McpMutation {
    ...
}

    async fn projects(&self) -> ProjectMutation {
    ...
}

    async fn exec_approvals(&self) -> ExecApprovalMutation {
    ...
}

    async fn logs(&self) -> LogsMutation {
    ...
}

    async fn memory(&self) -> MemoryMutation {
    ...
}

    async fn hooks(&self) -> HooksMutation {
    ...
}

    async fn agents(&self) -> AgentMutation {
    ...
}

    async fn voicewake(&self) -> VoicewakeMutation {
    ...
}

    async fn browser(&self) -> BrowserMutation {
    ...
}
}

// ── System ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct SystemMutation;

#[Object]
impl SystemMutation {
    /// Broadcast a system event.
    async fn event(
        &self,
        ctx: &Context<'_>,
        event: String,
        payload: Option<Json>,
    ) -> Result<BoolResult> {

    /// Touch activity timestamp.
    async fn set_heartbeats(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    /// Trigger wake functionality.
    async fn wake(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    /// Set talk mode.
    async fn talk_mode(&self, ctx: &Context<'_>, mode: String) -> Result<BoolResult> {
    ...
}

    /// Check for and run updates.
    async fn update_run(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}
}

// ── Node ────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct NodeMutation;

#[Object]
impl NodeMutation {
    /// Forward RPC request to a node.
    async fn invoke(&self, ctx: &Context<'_>, input: Json) -> Result<Json> {

    /// Rename a connected node.
    async fn rename(
        &self,
        ctx: &Context<'_>,
        node_id: String,
        display_name: String,
    ) -> Result<BoolResult> {
    ...
}

    /// Request pairing with a new node.
    async fn pair_request(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    /// Approve node pairing.
    async fn pair_approve(&self, ctx: &Context<'_>, request_id: String) -> Result<BoolResult> {
    ...
}

    /// Reject node pairing.
    async fn pair_reject(&self, ctx: &Context<'_>, request_id: String) -> Result<BoolResult> {
    ...
}

    /// Verify node pairing signature.
    async fn pair_verify(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}
}

// ── Device ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct DeviceMutation;

#[Object]
impl DeviceMutation {
    async fn pair_approve(&self, ctx: &Context<'_>, device_id: String) -> Result<BoolResult> {

    async fn pair_reject(&self, ctx: &Context<'_>, device_id: String) -> Result<BoolResult> {
    ...
}

    async fn token_rotate(&self, ctx: &Context<'_>, device_id: String) -> Result<BoolResult> {
    ...
}

    async fn token_revoke(&self, ctx: &Context<'_>, device_id: String) -> Result<BoolResult> {
    ...
}
}

// ── Chat ────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ChatMutation;

#[Object]
impl ChatMutation {
    /// Send a chat message.
    async fn send(
        &self,
        ctx: &Context<'_>,
        message: String,
        session_key: Option<String>,
        model: Option<String>,
    ) -> Result<BoolResult> {

    /// Abort active chat response.
    async fn abort(&self, ctx: &Context<'_>, session_key: Option<String>) -> Result<BoolResult> {
    ...
}

    /// Cancel queued chat messages.
    async fn cancel_queued(
        &self,
        ctx: &Context<'_>,
        session_key: Option<String>,
    ) -> Result<BoolResult> {
    ...
}

    /// Clear chat history for session.
    async fn clear(&self, ctx: &Context<'_>, session_key: Option<String>) -> Result<BoolResult> {
    ...
}

    /// Compact chat messages.
    async fn compact(&self, ctx: &Context<'_>, session_key: Option<String>) -> Result<BoolResult> {
    ...
}

    /// Inject a message into chat history.
    async fn inject(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}
}

// ── Sessions ────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct SessionMutation;

#[Object]
impl SessionMutation {
    /// Switch active session.
    async fn switch(&self, ctx: &Context<'_>, key: String) -> Result<BoolResult> {

    /// Fork session to new session.
    async fn fork(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    /// Patch session metadata.
    async fn patch(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    /// Reset session history.
    async fn reset(&self, ctx: &Context<'_>, key: String) -> Result<BoolResult> {
    ...
}

    /// Delete a session.
    async fn delete(&self, ctx: &Context<'_>, key: String) -> Result<BoolResult> {
    ...
}

    /// Clear all sessions.
    async fn clear_all(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    /// Compact all sessions.
    async fn compact(&self, ctx: &Context<'_>, key: Option<String>) -> Result<BoolResult> {
    ...
}

    /// Create a shareable session link.
    async fn share_create(&self, ctx: &Context<'_>, input: Json) -> Result<SessionShareResult> {
    ...
}

    /// Revoke a shared session link.
    async fn share_revoke(&self, ctx: &Context<'_>, share_id: String) -> Result<BoolResult> {
    ...
}
}

// ── Channels ────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ChannelMutation;

#[Object]
impl ChannelMutation {
    async fn add(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn remove(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn update(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn logout(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn approve_sender(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn deny_sender(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}
}

// ── Config ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ConfigMutation;

#[Object]
impl ConfigMutation {
    /// Set a config value.
    async fn set(&self, ctx: &Context<'_>, path: String, value: Json) -> Result<BoolResult> {

    /// Apply full config.
    async fn apply(&self, ctx: &Context<'_>, config: Json) -> Result<BoolResult> {
    ...
}

    /// Patch config.
    async fn patch(&self, ctx: &Context<'_>, patch: Json) -> Result<BoolResult> {
    ...
}
}

// ── Cron ────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct CronMutation;

#[Object]
impl CronMutation {
    async fn add(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn update(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn remove(&self, ctx: &Context<'_>, id: String) -> Result<BoolResult> {
    ...
}

    /// Trigger a cron job immediately.
    async fn run(&self, ctx: &Context<'_>, id: String) -> Result<BoolResult> {
    ...
}
}

// ── Heartbeat ───────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct HeartbeatMutation;

#[Object]
impl HeartbeatMutation {
    async fn update(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn run(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}
}

// ── TTS ─────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct TtsMutation;

#[Object]
impl TtsMutation {
    async fn enable(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn disable(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    async fn convert(&self, ctx: &Context<'_>, audio: String) -> Result<TtsConvertResult> {
    ...
}

    async fn set_provider(&self, ctx: &Context<'_>, provider: String) -> Result<BoolResult> {
    ...
}
}

// ── STT ─────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct SttMutation;

#[Object]
impl SttMutation {
    async fn transcribe(&self, ctx: &Context<'_>, input: Json) -> Result<TranscriptionResult> {

    async fn set_provider(&self, ctx: &Context<'_>, provider: String) -> Result<BoolResult> {
    ...
}
}

// ── Voice ───────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct VoiceMutation;

#[Object]
impl VoiceMutation {
    async fn save_key(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn save_settings(&self, ctx: &Context<'_>, settings: Json) -> Result<BoolResult> {
    ...
}

    async fn remove_key(&self, ctx: &Context<'_>, provider: String) -> Result<BoolResult> {
    ...
}

    async fn toggle_provider(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn session_override_set(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn session_override_clear(
        &self,
        ctx: &Context<'_>,
        session_key: String,
    ) -> Result<BoolResult> {
    ...
}

    async fn channel_override_set(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn channel_override_clear(
        &self,
        ctx: &Context<'_>,
        channel_key: String,
    ) -> Result<BoolResult> {
    ...
}
}

// ── Skills ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct SkillsMutation;

#[Object]
impl SkillsMutation {
    async fn install(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn remove(&self, ctx: &Context<'_>, source: String) -> Result<BoolResult> {
    ...
}

    async fn update(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn repos_remove(&self, ctx: &Context<'_>, source: String) -> Result<BoolResult> {
    ...
}

    async fn emergency_disable(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    async fn trust(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn enable(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn disable(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn install_dep(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}
}

// ── Models ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ModelMutation;

#[Object]
impl ModelMutation {
    async fn enable(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn disable(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn detect_supported(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    async fn test(&self, ctx: &Context<'_>, input: Json) -> Result<ModelTestResult> {
    ...
}
}

// ── Providers ───────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ProviderMutation;

#[Object]
impl ProviderMutation {
    async fn save_key(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn validate_key(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn save_model(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn save_models(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn remove_key(&self, ctx: &Context<'_>, provider: String) -> Result<BoolResult> {
    ...
}

    async fn add_custom(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn oauth_start(
        &self,
        ctx: &Context<'_>,
        provider: String,
    ) -> Result<ProviderOAuthStartResult> {
    ...
}

    async fn oauth_complete(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    /// Local LLM mutations.
    async fn local(&self) -> LocalLlmMutation {
    ...
}
}

#[derive(Default)]
pub struct LocalLlmMutation;

#[Object]
impl LocalLlmMutation {
    async fn configure(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn configure_custom(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn remove_model(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}
}

// ── MCP ─────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct McpMutation;

#[Object]
impl McpMutation {
    async fn add(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn remove(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn enable(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn disable(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn restart(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn reauth(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn update(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn oauth_start(&self, ctx: &Context<'_>, name: String) -> Result<McpOAuthStartResult> {
    ...
}

    async fn oauth_complete(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}
}

// ── Projects ────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ProjectMutation;

#[Object]
impl ProjectMutation {
    async fn upsert(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn delete(&self, ctx: &Context<'_>, id: String) -> Result<BoolResult> {
    ...
}

    async fn detect(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}
}

// ── Exec Approvals ──────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ExecApprovalMutation;

#[Object]
impl ExecApprovalMutation {
    async fn set(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {

    async fn set_node_config(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn request(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn resolve(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}
}

// ── Logs ────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct LogsMutation;

#[Object]
impl LogsMutation {
    async fn ack(&self, ctx: &Context<'_>) -> Result<BoolResult> {
}

// ── Memory ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct MemoryMutation;

#[Object]
impl MemoryMutation {
    async fn update_config(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
}

// ── Hooks ───────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct HooksMutation;

#[Object]
impl HooksMutation {
    async fn enable(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {

    async fn disable(&self, ctx: &Context<'_>, name: String) -> Result<BoolResult> {
    ...
}

    async fn save(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    async fn reload(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}
}

// ── Agents ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct AgentMutation;

#[Object]
impl AgentMutation {
    /// Run agent with parameters.
    async fn run(&self, ctx: &Context<'_>, input: Json) -> Result<Json> {

    /// Run agent and wait for completion.
    async fn run_wait(&self, ctx: &Context<'_>, input: Json) -> Result<Json> {
    ...
}

    /// Update agent identity.
    async fn update_identity(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
    ...
}

    /// Update agent soul/personality.
    async fn update_soul(&self, ctx: &Context<'_>, soul: String) -> Result<BoolResult> {
    ...
}
}

// ── Voicewake ───────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct VoicewakeMutation;

#[Object]
impl VoicewakeMutation {
    async fn set(&self, ctx: &Context<'_>, input: Json) -> Result<BoolResult> {
}

// ── Browser ─────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct BrowserMutation;

#[Object]
impl BrowserMutation {
    async fn request(&self, ctx: &Context<'_>, input: Json) -> Result<Json> {
}
