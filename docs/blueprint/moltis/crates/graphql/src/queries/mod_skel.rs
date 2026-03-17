//! GraphQL query resolvers, organized by service namespace.
//!
//! Resolvers call domain services directly through the `Services` bundle —
//! no RPC string-based dispatch or `ServiceCaller` indirection.

use async_graphql::{Context, Object, Result};

use crate::{
    error::{from_service, from_service_json},
    scalars::Json,
    services,
    types::{
        AgentIdentity, BoolResult, ChannelInfo, ChannelSendersResult, ChatRawPrompt, CronJob,
        CronRunRecord, CronStatus, ExecApprovalConfig, ExecNodeConfig, HealthInfo, HeartbeatStatus,
        HookInfo, LocalSystemInfo, LogListResult, LogStatus, LogTailResult, McpServer, McpTool,
        MemoryConfig, MemoryStatus, ModelInfo, NodeDescription, NodeInfo, Project, ProjectContext,
        ProviderInfo, SecurityScanResult, SecurityStatus, SessionActiveResult, SessionBranch,
        SessionEntry, SessionShareResult, SkillInfo, SkillRepo, StatusInfo, SttStatus,
        SystemPresence, TtsStatus, UsageCost, UsageStatus, VoiceConfig, VoicewakeConfig,
        VoxtralRequirements,
    },
};

// ── Root ────────────────────────────────────────────────────────────────────

/// Root query type composing all namespace queries.
#[derive(Default)]
pub struct QueryRoot;

#[Object]
impl QueryRoot {
    /// Gateway health check.
    async fn health(&self, ctx: &Context<'_>) -> Result<HealthInfo> {

    /// Gateway status with hostname, version, connections, uptime.
    async fn status(&self, ctx: &Context<'_>) -> Result<StatusInfo> {
    ...
}

    /// System queries (presence, heartbeat).
    async fn system(&self) -> SystemQuery {
    ...
}

    /// Node management queries.
    async fn node(&self) -> NodeQuery {
    ...
}

    /// Chat queries (history, context).
    async fn chat(&self) -> ChatQuery {
    ...
}

    /// Session queries.
    async fn sessions(&self) -> SessionQuery {
    ...
}

    /// Channel queries.
    async fn channels(&self) -> ChannelQuery {
    ...
}

    /// Configuration queries.
    async fn config(&self) -> ConfigQuery {
    ...
}

    /// Cron job queries.
    async fn cron(&self) -> CronQuery {
    ...
}

    /// Heartbeat queries.
    async fn heartbeat(&self) -> HeartbeatQuery {
    ...
}

    /// Log queries.
    async fn logs(&self) -> LogsQuery {
    ...
}

    /// TTS queries.
    async fn tts(&self) -> TtsQuery {
    ...
}

    /// STT queries.
    async fn stt(&self) -> SttQuery {
    ...
}

    /// Voice configuration queries.
    async fn voice(&self) -> VoiceQuery {
    ...
}

    /// Skills queries.
    async fn skills(&self) -> SkillsQuery {
    ...
}

    /// Model queries.
    async fn models(&self) -> ModelQuery {
    ...
}

    /// Provider queries.
    async fn providers(&self) -> ProviderQuery {
    ...
}

    /// MCP server queries.
    async fn mcp(&self) -> McpQuery {
    ...
}

    /// Usage and cost queries.
    async fn usage(&self) -> UsageQuery {
    ...
}

    /// Execution approval queries.
    async fn exec_approvals(&self) -> ExecApprovalQuery {
    ...
}

    /// Project queries.
    async fn projects(&self) -> ProjectQuery {
    ...
}

    /// Memory system queries.
    async fn memory(&self) -> MemoryQuery {
    ...
}

    /// Hook queries.
    async fn hooks(&self) -> HooksQuery {
    ...
}

    /// Agent queries.
    async fn agents(&self) -> AgentQuery {
    ...
}

    /// Voicewake configuration.
    async fn voicewake(&self) -> VoicewakeQuery {
    ...
}

    /// Device pairing queries.
    async fn device(&self) -> DeviceQuery {
    ...
}
}

// ── System ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct SystemQuery;

#[Object]
impl SystemQuery {
    /// Detailed client and node presence information.
    async fn presence(&self, ctx: &Context<'_>) -> Result<SystemPresence> {

    /// Last activity duration for the current client.
    async fn last_heartbeat(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}
}

// ── Node ────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct NodeQuery;

#[Object]
impl NodeQuery {
    /// List all connected nodes.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<NodeInfo>> {

    /// Get detailed info for a specific node.
    async fn describe(&self, ctx: &Context<'_>, node_id: String) -> Result<NodeDescription> {
    ...
}

    /// List pending pairing requests.
    async fn pair_requests(&self, ctx: &Context<'_>) -> Result<Json> {
    ...
}
}

// ── Chat ────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ChatQuery;

#[Object]
impl ChatQuery {
    /// Get chat history for a session.
    async fn history(&self, ctx: &Context<'_>, session_key: Option<String>) -> Result<Json> {

    /// Get chat context data.
    async fn context(&self, ctx: &Context<'_>, session_key: Option<String>) -> Result<Json> {
    ...
}

    /// Get rendered system prompt.
    async fn raw_prompt(
        &self,
        ctx: &Context<'_>,
        session_key: Option<String>,
    ) -> Result<ChatRawPrompt> {
    ...
}

    /// Get full context with rendering (OpenAI messages format).
    async fn full_context(&self, ctx: &Context<'_>, session_key: Option<String>) -> Result<Json> {
    ...
}
}

// ── Sessions ────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct SessionQuery;

#[Object]
impl SessionQuery {
    /// List all sessions.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<SessionEntry>> {

    /// Preview a session without switching.
    async fn preview(&self, ctx: &Context<'_>, key: String) -> Result<SessionEntry> {
    ...
}

    /// Search sessions by query.
    async fn search(&self, ctx: &Context<'_>, query: String) -> Result<Vec<SessionEntry>> {
    ...
}

    /// Resolve or auto-create a session.
    async fn resolve(&self, ctx: &Context<'_>, key: String) -> Result<SessionEntry> {
    ...
}

    /// Get session branches.
    async fn branches(&self, ctx: &Context<'_>, key: Option<String>) -> Result<Vec<SessionBranch>> {
    ...
}

    /// List shared session links.
    async fn shares(
        &self,
        ctx: &Context<'_>,
        key: Option<String>,
    ) -> Result<Vec<SessionShareResult>> {
    ...
}

    /// Whether this session has an active run (LLM is responding).
    async fn active(&self, ctx: &Context<'_>, session_key: String) -> Result<SessionActiveResult> {
    ...
}
}

// ── Channels ────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ChannelQuery;

#[Object]
impl ChannelQuery {
    /// Get channel status.
    async fn status(&self, ctx: &Context<'_>) -> Result<BoolResult> {

    /// List all channels.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<ChannelInfo>> {
    ...
}

    /// List pending channel senders.
    async fn senders(&self, ctx: &Context<'_>) -> Result<ChannelSendersResult> {
    ...
}
}

// ── Config ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ConfigQuery;

#[Object]
impl ConfigQuery {
    /// Get config value at a path. Returns dynamic user-defined config data.
    async fn get(&self, ctx: &Context<'_>, path: Option<String>) -> Result<Json> {

    /// Get config schema definition. Returns dynamic JSON schema.
    async fn schema(&self, ctx: &Context<'_>) -> Result<Json> {
    ...
}
}

// ── Cron ────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct CronQuery;

#[Object]
impl CronQuery {
    /// List all cron jobs.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<CronJob>> {

    /// Get cron status.
    async fn status(&self, ctx: &Context<'_>) -> Result<CronStatus> {
    ...
}

    /// Get run history for a cron job.
    async fn runs(&self, ctx: &Context<'_>, job_id: String) -> Result<Vec<CronRunRecord>> {
    ...
}
}

// ── Heartbeat ───────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct HeartbeatQuery;

#[Object]
impl HeartbeatQuery {
    /// Get heartbeat configuration and status.
    async fn status(&self, ctx: &Context<'_>) -> Result<HeartbeatStatus> {

    /// Get heartbeat run history.
    async fn runs(&self, ctx: &Context<'_>, limit: Option<u64>) -> Result<Vec<CronRunRecord>> {
    ...
}
}

// ── Logs ────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct LogsQuery;

#[Object]
impl LogsQuery {
    /// Stream log tail.
    async fn tail(&self, ctx: &Context<'_>, lines: Option<u64>) -> Result<LogTailResult> {

    /// List logs.
    async fn list(&self, ctx: &Context<'_>) -> Result<LogListResult> {
    ...
}

    /// Get log status.
    async fn status(&self, ctx: &Context<'_>) -> Result<LogStatus> {
    ...
}
}

// ── TTS ─────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct TtsQuery;

#[Object]
impl TtsQuery {
    /// Get TTS status.
    async fn status(&self, ctx: &Context<'_>) -> Result<TtsStatus> {

    /// Get available TTS providers.
    async fn providers(&self, ctx: &Context<'_>) -> Result<Vec<ProviderInfo>> {
    ...
}

    /// Generate a TTS test phrase.
    async fn generate_phrase(&self, _ctx: &Context<'_>) -> Result<String> {
    ...
}
}

// ── STT ─────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct SttQuery;

#[Object]
impl SttQuery {
    /// Get STT status.
    async fn status(&self, ctx: &Context<'_>) -> Result<SttStatus> {

    /// Get available STT providers.
    async fn providers(&self, ctx: &Context<'_>) -> Result<Vec<ProviderInfo>> {
    ...
}
}

// ── Voice ───────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct VoiceQuery;

#[Object]
impl VoiceQuery {
    /// Get voice configuration.
    async fn config(&self, _ctx: &Context<'_>) -> Result<VoiceConfig> {

    /// Get all voice providers with availability detection.
    async fn providers(&self, _ctx: &Context<'_>) -> Result<Vec<ProviderInfo>> {
    ...
}

    /// Fetch ElevenLabs voice catalog.
    async fn elevenlabs_catalog(&self, _ctx: &Context<'_>) -> Result<Json> {
    ...
}

    /// Check Voxtral local setup requirements.
    async fn voxtral_requirements(&self, _ctx: &Context<'_>) -> Result<VoxtralRequirements> {
    ...
}
}

// ── Skills ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct SkillsQuery;

#[Object]
impl SkillsQuery {
    /// List installed skills.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<SkillInfo>> {

    /// Get skills system status.
    async fn status(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    /// Get skills binaries.
    async fn bins(&self, ctx: &Context<'_>) -> Result<Json> {
    ...
}

    /// List skill repositories.
    async fn repos(&self, ctx: &Context<'_>) -> Result<Vec<SkillRepo>> {
    ...
}

    /// Get skill details.
    async fn detail(&self, ctx: &Context<'_>, name: String) -> Result<SkillInfo> {
    ...
}

    /// Get security status.
    async fn security_status(&self, ctx: &Context<'_>) -> Result<SecurityStatus> {
    ...
}

    /// Run security scan.
    async fn security_scan(&self, ctx: &Context<'_>) -> Result<SecurityScanResult> {
    ...
}
}

// ── Models ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ModelQuery;

#[Object]
impl ModelQuery {
    /// List enabled models.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<ModelInfo>> {

    /// List all available models.
    async fn list_all(&self, ctx: &Context<'_>) -> Result<Vec<ModelInfo>> {
    ...
}
}

// ── Providers ───────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ProviderQuery;

#[Object]
impl ProviderQuery {
    /// List available provider integrations.
    async fn available(&self, ctx: &Context<'_>) -> Result<Vec<ProviderInfo>> {

    /// Get OAuth status.
    async fn oauth_status(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    /// Local LLM queries.
    async fn local(&self) -> LocalLlmQuery {
    ...
}
}

#[derive(Default)]
pub struct LocalLlmQuery;

#[Object]
impl LocalLlmQuery {
    /// Get system information for local LLM.
    async fn system_info(&self, ctx: &Context<'_>) -> Result<LocalSystemInfo> {

    /// List available local models.
    async fn models(&self, ctx: &Context<'_>) -> Result<Vec<ModelInfo>> {
    ...
}

    /// Get local LLM status.
    async fn status(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    /// Search HuggingFace models.
    async fn search_hf(&self, ctx: &Context<'_>, query: String) -> Result<Json> {
    ...
}
}

// ── MCP ─────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct McpQuery;

#[Object]
impl McpQuery {
    /// List MCP servers.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<McpServer>> {

    /// Get MCP system status.
    async fn status(&self, ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}

    /// Get MCP server tools.
    async fn tools(&self, ctx: &Context<'_>, name: Option<String>) -> Result<Vec<McpTool>> {
    ...
}
}

// ── Usage ───────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct UsageQuery;

#[Object]
impl UsageQuery {
    /// Get usage statistics.
    async fn status(&self, ctx: &Context<'_>) -> Result<UsageStatus> {

    /// Calculate cost for a usage period.
    async fn cost(&self, ctx: &Context<'_>) -> Result<UsageCost> {
    ...
}
}

// ── Exec Approvals ──────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ExecApprovalQuery;

#[Object]
impl ExecApprovalQuery {
    /// Get execution approval settings.
    async fn get(&self, ctx: &Context<'_>) -> Result<ExecApprovalConfig> {

    /// Get node-specific approval settings.
    async fn node_config(&self, ctx: &Context<'_>) -> Result<ExecNodeConfig> {
    ...
}
}

// ── Projects ────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct ProjectQuery;

#[Object]
impl ProjectQuery {
    /// List all projects.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<Project>> {

    /// Get a project by ID.
    async fn get(&self, ctx: &Context<'_>, id: String) -> Result<Project> {
    ...
}

    /// Get project context.
    async fn context(&self, ctx: &Context<'_>, id: String) -> Result<ProjectContext> {
    ...
}

    /// Path completion for projects.
    async fn complete_path(&self, ctx: &Context<'_>, prefix: String) -> Result<Vec<String>> {
    ...
}
}

// ── Memory ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct MemoryQuery;

#[Object]
impl MemoryQuery {
    /// Get memory system status.
    async fn status(&self, _ctx: &Context<'_>) -> Result<MemoryStatus> {

    /// Get memory configuration.
    async fn config(&self, _ctx: &Context<'_>) -> Result<MemoryConfig> {
    ...
}

    /// Get QMD status.
    async fn qmd_status(&self, _ctx: &Context<'_>) -> Result<BoolResult> {
    ...
}
}

// ── Hooks ───────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct HooksQuery;

#[Object]
impl HooksQuery {
    /// List discovered hooks with stats.
    async fn list(&self, ctx: &Context<'_>) -> Result<Vec<HookInfo>> {
}

// ── Agents ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct AgentQuery;

#[Object]
impl AgentQuery {
    /// List available agents.
    async fn list(&self, ctx: &Context<'_>) -> Result<Json> {

    /// Get agent identity.
    async fn identity(&self, ctx: &Context<'_>) -> Result<AgentIdentity> {
    ...
}
}

// ── Voicewake ───────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct VoicewakeQuery;

#[Object]
impl VoicewakeQuery {
    /// Get wake word configuration.
    async fn get(&self, ctx: &Context<'_>) -> Result<VoicewakeConfig> {
}

// ── Device ──────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct DeviceQuery;

#[Object]
impl DeviceQuery {
    /// List paired devices.
    async fn pair_requests(&self, _ctx: &Context<'_>) -> Result<Json> {
}
