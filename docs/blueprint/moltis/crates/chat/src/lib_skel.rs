use std::{
    cmp::Ordering,
    collections::{BTreeMap, HashMap, HashSet},
    ffi::OsStr,
    path::{Path, PathBuf},
    process::Stdio,
    sync::Arc,
    time::{Duration, Instant},
};

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    serde_json::Value,
    tokio::{
        sync::{Mutex, OnceCell, OwnedSemaphorePermit, RwLock, Semaphore, mpsc},
        task::AbortHandle,
    },
    tokio_stream::StreamExt,
    tracing::{debug, info, warn},
};

use moltis_config::{MessageQueueMode, ToolMode};

use {
    moltis_agents::{
        AgentRunError, ChatMessage, ContentPart, UserContent,
        model::{StreamEvent, values_to_chat_messages},
        multimodal::parse_data_uri,
        prompt::{
            PromptHostRuntimeContext, PromptNodeInfo, PromptNodesRuntimeContext,
            PromptRuntimeContext, PromptSandboxRuntimeContext, VOICE_REPLY_SUFFIX,
            build_system_prompt_minimal_runtime, build_system_prompt_with_session_runtime,
        },
        runner::{RunnerEvent, run_agent_loop_streaming},
        tool_registry::{AgentTool, ToolRegistry},
    },
    moltis_providers::{ProviderRegistry, raw_model_id},
    moltis_sessions::{
        ContentBlock, MessageContent, PersistedMessage,
        message::{PersistedFunction, PersistedToolCall},
        metadata::{SessionEntry, SqliteSessionMetadata},
        store::SessionStore,
    },
    moltis_skills::discover::SkillDiscoverer,
    moltis_tools::policy::{ToolPolicy, profile_tools},
};

pub mod chat_error;
pub mod error;
pub mod runtime;

pub use runtime::{ChatRuntime, TtsOverride};
use {
    chat_error::parse_chat_error,
    moltis_service_traits::{ChatService, ModelService, ServiceError, ServiceResult},
};

/// Extract preview text from a single message JSON value.
fn extract_preview_from_value(msg: &Value) -> Option<String> {
    ...
}

/// Placeholder to match the old `BroadcastOpts` pattern. All fields are ignored;
/// the trait's `broadcast` always uses default behaviour.
#[derive(Default)]
pub struct BroadcastOpts {
    ...
}

/// Compatibility shim: delegates to [`ChatRuntime::broadcast`].
///
/// Matches the old `broadcast(state, topic, payload, opts)` signature so that
/// the hundreds of call sites inside this crate need no change.
async fn broadcast(
    state: &Arc<dyn ChatRuntime>,
    event: &str,
    payload: Value,
    _opts: BroadcastOpts,
) {
    ...
}

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram, labels, llm as llm_metrics};

/// Convert session-crate `MessageContent` to agents-crate `UserContent`.
///
/// The two types have different image representations:
/// - `ContentBlock::ImageUrl` stores a data URI string
/// - `ContentPart::Image` stores separated `media_type` + `data` fields
fn to_user_content(mc: &MessageContent) -> UserContent {
    ...
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
enum ReplyMedium {
    ...
}

#[must_use]
fn truncate_at_char_boundary(text: &str, max_bytes: usize) -> &str {
    ...
}

#[derive(Debug, Deserialize)]
struct InputChannelMeta {
    ...
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum InputMessageKind {
    ...
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum InputMediumParam {
    ...
}

/// Typed broadcast payload for the "final" chat event.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ChatFinalBroadcast {
    ...
}

/// Typed broadcast payload for the "error" chat event.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ChatErrorBroadcast {
    ...
}

struct AssistantTurnOutput {
    ...
}

#[derive(Debug, Clone, Copy, Default)]
struct SessionTokenUsage {
    ...
}

#[must_use]
fn session_token_usage_from_messages(messages: &[Value]) -> SessionTokenUsage {
    ...
}

#[must_use]
fn assistant_message_is_visible(message: &Value) -> bool {
    ...
}

#[must_use]
fn estimate_text_tokens(text: &str) -> u64 {
    ...
}

fn now_ms() -> u64 {
    ...
}

pub fn normalize_model_key(value: &str) -> String {
    ...
}

fn normalize_provider_key(value: &str) -> String {
    ...
}

fn subscription_provider_rank(provider_name: &str) -> usize {
    ...
}

#[allow(dead_code)]
fn is_allowlist_exempt_provider(provider_name: &str) -> bool {
    ...
}

/// Returns `true` if the model matches the allowlist patterns.
/// An empty pattern list means all models are allowed.
/// Matching is case-insensitive against the full model ID, raw model ID, and
/// display name:
/// - patterns with digits use exact-or-suffix matching (boundary aware)
/// - patterns without digits use substring matching
///
/// This keeps precise model pins like "gpt 5.2" from matching variants such as
/// "gpt-5.2-chat-latest", while still allowing broad buckets like "mini".
#[allow(dead_code)]
fn allowlist_pattern_matches_key(pattern: &str, key: &str) -> bool {
    ...
}

#[allow(dead_code)]
pub fn model_matches_allowlist(model: &moltis_providers::ModelInfo, patterns: &[String]) -> bool {
    ...
}

#[allow(dead_code)]
pub fn model_matches_allowlist_with_provider(
    model: &moltis_providers::ModelInfo,
    provider_name: Option<&str>,
    patterns: &[String],
) -> bool {
    ...
}

fn provider_filter_from_params(params: &Value) -> Option<String> {
    ...
}

fn provider_matches_filter(model_provider: &str, provider_filter: Option<&str>) -> bool {
    ...
}

fn probe_max_parallel_per_provider(params: &Value) -> usize {
    ...
}

fn provider_model_entry(model_id: &str, display_name: &str) -> Value {
    ...
}

fn push_provider_model(
    grouped: &mut BTreeMap<String, Vec<Value>>,
    provider_name: &str,
    model_id: &str,
    display_name: &str,
) {
    ...
}

const PROBE_RATE_LIMIT_INITIAL_BACKOFF_MS: u64 = 1_000;
const PROBE_RATE_LIMIT_MAX_BACKOFF_MS: u64 = 30_000;

#[derive(Debug, Clone, Copy)]
struct ProbeRateLimitState {
    ...
}

#[derive(Debug, Default)]
struct ProbeRateLimiter {
    ...
}

impl ProbeRateLimiter {
    async fn remaining_backoff(&self, provider: &str) -> Option<Duration> {

    async fn mark_rate_limited(&self, provider: &str) -> Duration {
    ...
}

    async fn clear(&self, provider: &str) {
    ...
}
}

fn next_probe_rate_limit_backoff_ms(previous_ms: Option<u64>) -> u64 {
    ...
}

fn is_probe_rate_limited_error(error_obj: &Value, error_text: &str) -> bool {
    ...
}

#[derive(Debug)]
struct ProbeProviderLimiter {
    ...
}

impl ProbeProviderLimiter {
    fn new(permits_per_provider: usize) -> Self {

    async fn acquire(
        &self,
        provider: &str,
    ) -> Result<OwnedSemaphorePermit, tokio::sync::AcquireError> {
    ...
}
}

#[derive(Debug)]
enum ProbeStatus {
    ...
}

#[derive(Debug)]
struct ProbeOutcome {
    ...
}

/// Run a single model probe: acquire concurrency permits, respect rate-limit
/// backoff, send a "ping" completion, and classify the result.
async fn run_single_probe(
    model_id: String,
    display_name: String,
    provider_name: String,
    provider: Arc<dyn moltis_agents::model::LlmProvider>,
    limiter: Arc<Semaphore>,
    provider_limiter: Arc<ProbeProviderLimiter>,
    rate_limiter: Arc<ProbeRateLimiter>,
) -> ProbeOutcome {
    ...
}

fn parse_input_medium(params: &Value) -> Option<ReplyMedium> {
    ...
}

fn explicit_reply_medium_override(text: &str) -> Option<ReplyMedium> {
    ...
}

fn infer_reply_medium(params: &Value, text: &str) -> ReplyMedium {
    ...
}

fn runtime_datetime_prompt_tail(runtime_context: Option<&PromptRuntimeContext>) -> Option<String> {
    ...
}

fn apply_voice_reply_suffix(
    system_prompt: String,
    desired_reply_medium: ReplyMedium,
    runtime_context: Option<&PromptRuntimeContext>,
) -> String {
    ...
}

fn parse_explicit_shell_command(text: &str) -> Option<&str> {
    ...
}

fn capped_tool_result_payload(result: &Value, max_len: usize) -> Value {
    ...
}

fn shell_reply_text_from_exec_result(result: &Value) -> String {
    ...
}

fn is_safe_user_audio_filename(filename: &str) -> bool {
    ...
}

fn user_audio_path_from_params(params: &Value, session_key: &str) -> Option<String> {
    ...
}

fn detect_runtime_shell() -> Option<String> {
    ...
}

async fn detect_host_sudo_access() -> (Option<bool>, Option<String>) {
    ...
}

async fn detect_host_root_user() -> Option<bool> {
    ...
}

/// Pre-loaded persona data used to build the system prompt.
struct PromptPersona {
    ...
}

fn resolve_prompt_agent_id(session_entry: Option<&SessionEntry>) -> String {
    ...
}

/// Load identity, user profile, soul, and workspace text for one agent.
///
/// Both `run_with_tools` and `run_streaming` need the same persona data;
/// this function avoids duplicating the merge logic.
fn load_prompt_persona_for_agent(agent_id: &str) -> PromptPersona {
    ...
}

fn load_prompt_persona_for_session(session_entry: Option<&SessionEntry>) -> PromptPersona {
    ...
}

#[derive(Default)]
struct ChannelRuntimeContext {
    ...
}

fn infer_channel_chat_type(channel_type: &str, chat_id: &str) -> Option<String> {
    ...
}

fn resolve_channel_runtime_context(
    session_key: &str,
    session_entry: Option<&SessionEntry>,
) -> ChannelRuntimeContext {
    ...
}

async fn build_prompt_runtime_context(
    state: &Arc<dyn ChatRuntime>,
    provider: &Arc<dyn moltis_agents::model::LlmProvider>,
    session_key: &str,
    session_entry: Option<&SessionEntry>,
) -> PromptRuntimeContext {
    ...
}

fn refresh_runtime_prompt_time(host: &mut PromptHostRuntimeContext) {
    ...
}

fn server_prompt_timezone(configured_timezone: Option<&str>) -> String {
    ...
}

fn prompt_now_for_timezone(timezone: Option<&str>) -> String {
    ...
}

fn prompt_today_for_timezone(timezone: Option<&str>) -> String {
    ...
}

fn normalized_iana_timezone(timezone: Option<&str>) -> Option<String> {
    ...
}

fn default_user_prompt_timezone() -> Option<String> {
    ...
}

fn apply_request_runtime_context(host: &mut PromptHostRuntimeContext, params: &Value) {
    ...
}

fn prompt_sandbox_no_network_state(backend: &str, configured_no_network: bool) -> Option<bool> {
    ...
}

fn effective_tool_policy(config: &moltis_config::MoltisConfig) -> ToolPolicy {
    ...
}

fn apply_runtime_tool_filters(
    base: &ToolRegistry,
    config: &moltis_config::MoltisConfig,
    _skills: &[moltis_skills::types::SkillMetadata],
    mcp_disabled: bool,
) -> ToolRegistry {
    ...
}

// ── Disabled Models Store ────────────────────────────────────────────────────

/// Persistent store for disabled model IDs.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DisabledModelsStore {
    ...
}

/// Metadata for a model that failed at runtime due to provider support/account limits.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnsupportedModelInfo {
    ...
}

impl DisabledModelsStore {
    fn config_path() -> Option<PathBuf> {

    /// Load disabled models from config file.
    pub fn load() -> Self {
    ...
}

    /// Save disabled models to config file.
    pub fn save(&self) -> error::Result<()> {
    ...
}

    /// Disable a model by ID.
    pub fn disable(&mut self, model_id: &str) -> bool {
    ...
}

    /// Enable a model by ID (remove from disabled set).
    pub fn enable(&mut self, model_id: &str) -> bool {
    ...
}

    /// Check if a model is disabled.
    pub fn is_disabled(&self, model_id: &str) -> bool {
    ...
}

    /// Mark a model as unsupported with a human-readable reason.
    pub fn mark_unsupported(
        &mut self,
        model_id: &str,
        detail: &str,
        provider: Option<&str>,
    ) -> bool {
    ...
}

    /// Clear unsupported status when a model succeeds again.
    pub fn clear_unsupported(&mut self, model_id: &str) -> bool {
    ...
}

    /// Get unsupported metadata for a model.
    pub fn unsupported_info(&self, model_id: &str) -> Option<&UnsupportedModelInfo> {
    ...
}
}

// ── LiveModelService ────────────────────────────────────────────────────────

pub struct LiveModelService {
    ...
}

impl LiveModelService {
    pub fn new(
        providers: Arc<RwLock<ProviderRegistry>>,
        disabled: Arc<RwLock<DisabledModelsStore>>,
        priority_models: Vec<String>,
    ) -> Self {

    /// Shared handle to the priority models list. Pass this to services
    /// that need to update model ordering at runtime (e.g. `save_model`).
    pub fn priority_models_handle(&self) -> Arc<RwLock<Vec<String>>> {
    ...
}

    fn build_priority_order(models: &[String]) -> HashMap<String, usize> {
    ...
}

    fn priority_rank(order: &HashMap<String, usize>, model: &moltis_providers::ModelInfo) -> usize {
    ...
}

    fn prioritize_models<'a>(
        order: &HashMap<String, usize>,
        models: impl Iterator<Item = &'a moltis_providers::ModelInfo>,
    ) -> Vec<&'a moltis_providers::ModelInfo> {

    async fn priority_order(&self) -> HashMap<String, usize> {
    ...
}

    /// Set the gateway state reference for broadcasting model updates.
    pub fn set_state(&self, state: Arc<dyn ChatRuntime>) {
    ...
}

    async fn broadcast_model_visibility_update(&self, model_id: &str, disabled: bool) {
    ...
}
}

fn normalize_model_lookup_key(value: &str) -> String {
    ...
}

fn model_id_provider(model_id: &str) -> Option<&str> {
    ...
}

fn levenshtein_distance(a: &str, b: &str) -> usize {
    ...
}

fn suggest_model_ids(
    requested_model_id: &str,
    available_model_ids: &[String],
    limit: usize,
) -> Vec<String> {
    ...
}

#[async_trait]
impl ModelService for LiveModelService {
    async fn list(&self) -> ServiceResult {

    async fn list_all(&self) -> ServiceResult {
    ...
}

    async fn disable(&self, params: Value) -> ServiceResult {
    ...
}

    async fn enable(&self, params: Value) -> ServiceResult {
    ...
}

    async fn detect_supported(&self, params: Value) -> ServiceResult {
    ...
}

    async fn test(&self, params: Value) -> ServiceResult {
    ...
}
}

// ── LiveChatService ─────────────────────────────────────────────────────────

/// A message that arrived while an agent run was already active on the session.
#[derive(Debug, Clone)]
struct QueuedMessage {
    ...
}

/// A tool call currently executing within an active agent run.
#[derive(Debug, Clone, Serialize)]
pub struct ActiveToolCall {
    ...
}

#[derive(Debug, Clone)]
struct ActiveAssistantDraft {
    ...
}

impl ActiveAssistantDraft {
    fn new(run_id: &str, model: &str, provider: &str, seq: Option<u64>) -> Self {

    fn append_text(&mut self, delta: &str) {
    ...
}

    fn set_reasoning(&mut self, reasoning: &str) {
    ...
}

    fn has_visible_content(&self) -> bool {
    ...
}

    fn to_persisted_message(&self) -> PersistedMessage {
    ...
}
}

fn build_persisted_tool_call(
    tool_call_id: impl Into<String>,
    tool_name: impl Into<String>,
    arguments: Option<Value>,
) -> PersistedToolCall {
    ...
}

fn build_tool_call_assistant_message(
    tool_call_id: impl Into<String>,
    tool_name: impl Into<String>,
    arguments: Option<Value>,
    seq: Option<u64>,
    run_id: Option<&str>,
) -> PersistedMessage {
    ...
}

async fn persist_tool_history_pair(
    session_store: &Arc<SessionStore>,
    session_key: &str,
    assistant_tool_call_msg: PersistedMessage,
    tool_result_msg: PersistedMessage,
    assistant_warn_context: &str,
    tool_result_warn_context: &str,
) {
    ...
}

pub struct LiveChatService {
    ...
}

impl LiveChatService {
    pub fn new(
        providers: Arc<RwLock<ProviderRegistry>>,
        model_store: Arc<RwLock<DisabledModelsStore>>,
        state: Arc<dyn ChatRuntime>,
        session_store: Arc<SessionStore>,
        session_metadata: Arc<SqliteSessionMetadata>,
    ) -> Self {

    pub fn with_failover(mut self, config: moltis_config::schema::FailoverConfig) -> Self {
    ...
}

    pub fn with_tools(mut self, registry: Arc<RwLock<ToolRegistry>>) -> Self {
    ...
}

    pub fn with_hooks(mut self, registry: moltis_common::hooks::HookRegistry) -> Self {
    ...
}

    pub fn with_hooks_arc(mut self, registry: Arc<moltis_common::hooks::HookRegistry>) -> Self {
    ...
}

    fn has_tools_sync(&self) -> bool {
    ...
}

    /// Return the per-session semaphore, creating one if absent.
    async fn session_semaphore(&self, key: &str) -> Arc<Semaphore> {
    ...
}

    async fn abort_run_handle(
        active_runs: &Arc<RwLock<HashMap<String, AbortHandle>>>,
        active_runs_by_session: &Arc<RwLock<HashMap<String, String>>>,
        terminal_runs: &Arc<RwLock<HashSet<String>>>,
        run_id: Option<&str>,
        session_key: Option<&str>,
    ) -> (Option<String>, bool) {
    ...
}

    async fn resolve_session_key_for_run(
        active_runs_by_session: &Arc<RwLock<HashMap<String, String>>>,
        run_id: Option<&str>,
        session_key: Option<&str>,
    ) -> Option<String> {
    ...
}

    async fn wait_for_event_forwarder(
        active_event_forwarders: &Arc<RwLock<HashMap<String, tokio::task::JoinHandle<String>>>>,
        session_key: &str,
    ) -> String {
    ...
}

    async fn persist_partial_assistant_on_abort(
        &self,
        session_key: &str,
    ) -> Option<(Value, Option<u32>)> {
    ...
}

    /// Resolve a provider from session metadata, history, or first registered.
    async fn resolve_provider(
        &self,
        session_key: &str,
        history: &[Value],
    ) -> error::Result<Arc<dyn moltis_agents::model::LlmProvider>> {
    ...
}

    /// Resolve the active session key for a connection.
    async fn session_key_for(&self, conn_id: Option<&str>) -> String {
    ...
}

    /// Resolve the project context prompt section for a session.
    async fn resolve_project_context(
        &self,
        session_key: &str,
        conn_id: Option<&str>,
    ) -> Option<String> {
    ...
}
}

#[async_trait]
impl ChatService for LiveChatService {
    #[tracing::instrument(skip(self, params), fields(session_id))]
    async fn send(&self, mut params: Value) -> ServiceResult {
        #[cfg(feature = "local-llm")]

    async fn send_sync(&self, params: Value) -> ServiceResult {
    ...
}

    async fn abort(&self, params: Value) -> ServiceResult {
    ...
}

    async fn cancel_queued(&self, params: Value) -> ServiceResult {
    ...
}

    async fn history(&self, params: Value) -> ServiceResult {
    ...
}

    async fn inject(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn clear(&self, params: Value) -> ServiceResult {
    ...
}

    async fn compact(&self, params: Value) -> ServiceResult {
    ...
}

    async fn context(&self, params: Value) -> ServiceResult {
    ...
}

    async fn raw_prompt(&self, params: Value) -> ServiceResult {
    ...
}

    /// Return the **full messages array** that would be sent to the LLM on the
    /// next call — system prompt + conversation history — in OpenAI format.
    async fn full_context(&self, params: Value) -> ServiceResult {
    ...
}

    async fn active(&self, params: Value) -> ServiceResult {
    ...
}

    async fn active_session_keys(&self) -> Vec<String> {
    ...
}

    async fn active_thinking_text(&self, session_key: &str) -> Option<String> {
    ...
}

    async fn active_voice_pending(&self, session_key: &str) -> bool {
    ...
}

    async fn peek(&self, params: Value) -> ServiceResult {
    ...
}
}

// ── Agent loop mode ─────────────────────────────────────────────────────────

async fn mark_unsupported_model(
    state: &Arc<dyn ChatRuntime>,
    model_store: &Arc<RwLock<DisabledModelsStore>>,
    model_id: &str,
    provider_name: &str,
    error_obj: &Value,
) {
    ...
}

async fn clear_unsupported_model(
    state: &Arc<dyn ChatRuntime>,
    model_store: &Arc<RwLock<DisabledModelsStore>>,
    model_id: &str,
) {
    ...
}

fn ordered_runner_event_callback() -> (
    Box<dyn Fn(RunnerEvent) + Send + Sync>,
    mpsc::UnboundedReceiver<RunnerEvent>,
) {
    ...
}

const CHANNEL_STREAM_BUFFER_SIZE: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct ChannelReplyTargetKey {
    ...
}

impl From<&moltis_channels::ChannelReplyTarget> for ChannelReplyTargetKey {
    fn from(target: &moltis_channels::ChannelReplyTarget) -> Self {
}

struct ChannelStreamWorker {
    ...
}

/// Fan out model deltas to channel stream workers (Telegram/Discord edit-in-place).
///
/// Workers are started eagerly so channel typing indicators remain active
/// during long-running tool execution before the first text delta arrives.
/// Stream-dedup only applies after at least one delta has been sent.
struct ChannelStreamDispatcher {
    ...
}

impl ChannelStreamDispatcher {
    async fn for_session(state: &Arc<dyn ChatRuntime>, session_key: &str) -> Option<Self> {

    async fn ensure_started(&mut self) {
    ...
}

    async fn send_delta(&mut self, delta: &str) {
    ...
}

    async fn finish(&mut self) {
    ...
}

    async fn send_terminal(&mut self, event: moltis_channels::StreamEvent) {
    ...
}

    async fn join_workers(&mut self) {
    ...
}

    async fn completed_target_keys(&self) -> HashSet<ChannelReplyTargetKey> {
    ...
}
}

async fn run_explicit_shell_command(
    state: &Arc<dyn ChatRuntime>,
    run_id: &str,
    tool_registry: &Arc<RwLock<ToolRegistry>>,
    session_store: &Arc<SessionStore>,
    terminal_runs: &Arc<RwLock<HashSet<String>>>,
    session_key: &str,
    command: &str,
    user_message_index: usize,
    accept_language: Option<String>,
    conn_id: Option<String>,
    client_seq: Option<u64>,
) -> AssistantTurnOutput {
    ...
}

const MAX_AGENT_MEMORY_WRITE_BYTES: usize = 50 * 1024;
const MEMORY_SEARCH_FETCH_MULTIPLIER: usize = 8;
const MEMORY_SEARCH_MIN_FETCH: usize = 25;

fn is_valid_agent_memory_leaf_name(name: &str) -> bool {
    ...
}

fn resolve_agent_memory_target_path(agent_id: &str, file: &str) -> anyhow::Result<PathBuf> {
    ...
}

fn is_path_in_agent_memory_scope(path: &Path, agent_id: &str) -> bool {
    ...
}

struct AgentScopedMemoryWriter {
    ...
}

impl AgentScopedMemoryWriter {
    fn new(manager: Arc<moltis_memory::manager::MemoryManager>, agent_id: String) -> Self {
}

#[async_trait]
impl moltis_agents::memory_writer::MemoryWriter for AgentScopedMemoryWriter {
    async fn write_memory(
        &self,
        file: &str,
        content: &str,
        append: bool,
    ) -> anyhow::Result<moltis_agents::memory_writer::MemoryWriteResult> {
}

struct AgentScopedMemorySearchTool {
    ...
}

impl AgentScopedMemorySearchTool {
    fn new(manager: Arc<moltis_memory::manager::MemoryManager>, agent_id: String) -> Self {
}

#[async_trait]
impl AgentTool for AgentScopedMemorySearchTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

struct AgentScopedMemoryGetTool {
    ...
}

impl AgentScopedMemoryGetTool {
    fn new(manager: Arc<moltis_memory::manager::MemoryManager>, agent_id: String) -> Self {
}

#[async_trait]
impl AgentTool for AgentScopedMemoryGetTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

struct AgentScopedMemorySaveTool {
    ...
}

impl AgentScopedMemorySaveTool {
    fn new(manager: Arc<moltis_memory::manager::MemoryManager>, agent_id: String) -> Self {
}

#[async_trait]
impl AgentTool for AgentScopedMemorySaveTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

fn install_agent_scoped_memory_tools(
    registry: &mut ToolRegistry,
    manager: &Arc<moltis_memory::manager::MemoryManager>,
    agent_id: &str,
) {
    ...
}

/// Resolve the effective tool mode for a provider.
///
/// Combines the provider's `tool_mode()` override with its `supports_tools()`
/// capability to determine how tools should be dispatched:
/// - `Native` — provider handles tool schemas via API (OpenAI function calling, etc.)
/// - `Text` — tools are described in the prompt; the runner parses tool calls from text
/// - `Off` — no tools at all
fn effective_tool_mode(provider: &dyn moltis_agents::model::LlmProvider) -> ToolMode {
    ...
}

async fn run_with_tools(
    state: &Arc<dyn ChatRuntime>,
    model_store: &Arc<RwLock<DisabledModelsStore>>,
    run_id: &str,
    provider: Arc<dyn moltis_agents::model::LlmProvider>,
    model_id: &str,
    tool_registry: &Arc<RwLock<ToolRegistry>>,
    user_content: &UserContent,
    provider_name: &str,
    history_raw: &[Value],
    session_key: &str,
    agent_id: &str,
    desired_reply_medium: ReplyMedium,
    project_context: Option<&str>,
    runtime_context: Option<&PromptRuntimeContext>,
    user_message_index: usize,
    skills: &[moltis_skills::types::SkillMetadata],
    hook_registry: Option<Arc<moltis_common::hooks::HookRegistry>>,
    accept_language: Option<String>,
    conn_id: Option<String>,
    session_store: Option<&Arc<SessionStore>>,
    mcp_disabled: bool,
    client_seq: Option<u64>,
    active_thinking_text: Option<Arc<RwLock<HashMap<String, String>>>>,
    active_tool_calls: Option<Arc<RwLock<HashMap<String, Vec<ActiveToolCall>>>>>,
    active_partial_assistant: Option<Arc<RwLock<HashMap<String, ActiveAssistantDraft>>>>,
    active_event_forwarders: &Arc<RwLock<HashMap<String, tokio::task::JoinHandle<String>>>>,
    terminal_runs: &Arc<RwLock<HashSet<String>>>,
) -> Option<AssistantTurnOutput> {
    ...
}

/// Compact a session's history by summarizing it with the given provider.
///
/// This is a standalone helper so `run_with_tools` can call it without
/// requiring `&self` on `LiveChatService`.
async fn compact_session(
    store: &Arc<SessionStore>,
    session_key: &str,
    provider: &Arc<dyn moltis_agents::model::LlmProvider>,
) -> error::Result<()> {
    ...
}

// ── Streaming mode (no tools) ───────────────────────────────────────────────

const STREAM_RETRYABLE_SERVER_PATTERNS: &[&str] = &[
    "http 500",
    "http 502",
    "http 503",
    "http 504",
    "internal server error",
    "service unavailable",
    "gateway timeout",
    "temporarily unavailable",
    "overloaded",
    "timeout",
    "connection reset",
];
const STREAM_SERVER_RETRY_DELAY_MS: u64 = 2_000;
const STREAM_SERVER_MAX_RETRIES: u8 = 1;
const STREAM_RATE_LIMIT_INITIAL_RETRY_MS: u64 = 2_000;
const STREAM_RATE_LIMIT_MAX_RETRY_MS: u64 = 60_000;
const STREAM_RATE_LIMIT_MAX_RETRIES: u8 = 10;

fn is_retryable_stream_server_error(msg: &str) -> bool {
    ...
}

fn next_stream_rate_limit_retry_ms(previous_ms: Option<u64>) -> u64 {
    ...
}

fn next_stream_retry_delay_ms(
    raw_error: &str,
    error_obj: &Value,
    server_retries_remaining: &mut u8,
    rate_limit_retries_remaining: &mut u8,
    rate_limit_backoff_ms: &mut Option<u64>,
) -> Option<u64> {
    ...
}

async fn run_streaming(
    state: &Arc<dyn ChatRuntime>,
    model_store: &Arc<RwLock<DisabledModelsStore>>,
    run_id: &str,
    provider: Arc<dyn moltis_agents::model::LlmProvider>,
    model_id: &str,
    user_content: &UserContent,
    provider_name: &str,
    history_raw: &[Value],
    session_key: &str,
    agent_id: &str,
    desired_reply_medium: ReplyMedium,
    project_context: Option<&str>,
    user_message_index: usize,
    _skills: &[moltis_skills::types::SkillMetadata],
    runtime_context: Option<&PromptRuntimeContext>,
    session_store: Option<&Arc<SessionStore>>,
    client_seq: Option<u64>,
    active_partial_assistant: Option<Arc<RwLock<HashMap<String, ActiveAssistantDraft>>>>,
    terminal_runs: &Arc<RwLock<HashSet<String>>>,
) -> Option<AssistantTurnOutput> {
    ...
}

/// Send a push notification when a chat response completes.
/// Only sends if push notifications are configured and there are subscribers.
#[cfg(feature = "push-notifications")]
async fn send_chat_push_notification(state: &Arc<dyn ChatRuntime>, session_key: &str, text: &str) {
    ...
}

/// Drain any pending channel reply targets for a session and send the
/// response text back to each originating channel via outbound.
/// Each delivery runs in its own spawned task so slow network calls
/// don't block each other or the chat pipeline.
async fn deliver_channel_replies(
    state: &Arc<dyn ChatRuntime>,
    session_key: &str,
    text: &str,
    desired_reply_medium: ReplyMedium,
    streamed_target_keys: &HashSet<ChannelReplyTargetKey>,
) {
    ...
}

/// Format buffered status log entries into a Telegram expandable blockquote HTML.
/// Returns an empty string if there are no entries.
fn format_logbook_html(entries: &[String]) -> String {
    ...
}

async fn send_channel_logbook_follow_up_to_targets(
    outbound: Arc<dyn moltis_channels::plugin::ChannelOutbound>,
    targets: Vec<moltis_channels::ChannelReplyTarget>,
    logbook_html: &str,
) {
    ...
}

fn format_channel_retry_message(error_obj: &Value, retry_after: Duration) -> String {
    ...
}

fn format_channel_error_message(error_obj: &Value) -> String {
    ...
}

/// Send a short retry status update to pending channel targets without draining
/// them. The final reply (or terminal error) will still use the same targets.
async fn send_retry_status_to_channels(
    state: &Arc<dyn ChatRuntime>,
    session_key: &str,
    error_obj: &Value,
    retry_after: Duration,
) {
    ...
}

/// Drain pending channel targets for a session and send a terminal error message.
async fn deliver_channel_error(state: &Arc<dyn ChatRuntime>, session_key: &str, error_obj: &Value) {
    ...
}

async fn deliver_channel_replies_to_targets(
    outbound: Arc<dyn moltis_channels::plugin::ChannelOutbound>,
    targets: Vec<moltis_channels::ChannelReplyTarget>,
    session_key: &str,
    text: &str,
    state: Arc<dyn ChatRuntime>,
    desired_reply_medium: ReplyMedium,
    status_log: Vec<String>,
    streamed_target_keys: &HashSet<ChannelReplyTargetKey>,
) {
    ...
}

#[derive(Debug, Deserialize)]
struct TtsStatusResponse {
    ...
}

#[derive(Debug, Serialize)]
struct TtsConvertRequest<'a> {
    ...
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TtsConvertResponse {
    ...
}

/// Generate TTS audio bytes for a web UI response.
///
/// Uses the session-level TTS override if configured, otherwise the global TTS
/// config. Returns raw audio bytes (OGG format) on success, `None` if TTS is
/// disabled or generation fails.
async fn generate_tts_audio(
    state: &Arc<dyn ChatRuntime>,
    session_key: &str,
    text: &str,
) -> error::Result<Vec<u8>> {
    ...
}

async fn build_tts_payload(
    state: &Arc<dyn ChatRuntime>,
    session_key: &str,
    target: &moltis_channels::ChannelReplyTarget,
    text: &str,
) -> Option<moltis_common::types::ReplyPayload> {
    ...
}

/// Buffer a tool execution status into the channel status log for a session.
/// The buffered entries are appended as a collapsible logbook when the final
/// response is delivered, instead of being sent as separate messages.
async fn send_tool_status_to_channels(
    state: &Arc<dyn ChatRuntime>,
    session_key: &str,
    tool_name: &str,
    arguments: &Value,
) {
    ...
}

/// Buffer a tool error result into the channel status log for a session.
/// Called from `ToolCallEnd` for failed tool calls only — success is implicit
/// and does not need a separate log entry.
async fn send_tool_result_to_channels(
    state: &Arc<dyn ChatRuntime>,
    session_key: &str,
    tool_name: &str,
    success: bool,
    error: &Option<String>,
    result: &Option<Value>,
) {
    ...
}

/// Format a human-readable error summary for a failed tool call.
fn format_tool_result_message(
    tool_name: &str,
    error: &Option<String>,
    result: &Option<Value>,
) -> String {
    ...
}

/// Format a human-readable tool execution message.
fn format_tool_status_message(tool_name: &str, arguments: &Value) -> String {
    ...
}

/// Truncate a URL for display (show domain + short path).
fn truncate_url(url: &str) -> String {
    ...
}

/// Send a screenshot to all pending channel targets for a session.
/// Uses `peek_channel_replies` so targets remain for the final text response.
async fn send_screenshot_to_channels(
    state: &Arc<dyn ChatRuntime>,
    session_key: &str,
    screenshot_data: &str,
    caption: Option<&str>,
) {
    ...
}

/// Send a native location pin to all pending channel targets for a session.
/// Uses `peek_channel_replies` so targets remain for the final text response.
async fn send_location_to_channels(
    state: &Arc<dyn ChatRuntime>,
    session_key: &str,
    latitude: f64,
    longitude: f64,
    title: Option<&str>,
) {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    struct DummyTool {
    ...
}

    struct StaticProvider {
    ...
}

    struct AbortThenContinueProvider {
    ...
}

    impl AbortThenContinueProvider {
        fn new() -> Self {
    }

    #[async_trait]
    impl LlmProvider for AbortThenContinueProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[Value],
        ) -> Result<moltis_agents::model::CompletionResponse> {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    struct StreamingTextToolProvider;

    #[async_trait]
    impl LlmProvider for StreamingTextToolProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[Value],
        ) -> Result<moltis_agents::model::CompletionResponse> {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    struct AutoCompactRegressionProvider {
    ...
}
    #[async_trait]
    impl LlmProvider for StaticProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[Value],
        ) -> Result<moltis_agents::model::CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[async_trait]
    impl LlmProvider for AutoCompactRegressionProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[Value],
        ) -> Result<moltis_agents::model::CompletionResponse> {
    ...
}

        fn context_window(&self) -> u32 {
    ...
}

        fn stream(
            &self,
            messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[async_trait]
    impl AgentTool for DummyTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> Value {
    ...
}

        async fn execute(&self, _params: Value) -> Result<Value> {
    ...
}
    }

    #[async_trait]
    impl AgentTool for MockExecTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> Value {
    ...
}

        async fn execute(&self, params: Value) -> Result<Value> {
    ...
}
    }

    struct MockChannelOutbound {
    ...
}

    struct RecordingChannelOutbound {
    ...
}

    struct MockChannelStreamOutbound {
    ...
}

    struct MockChatRuntime {
    ...
}

    impl MockChatRuntime {
        fn new() -> Self {

        fn with_channel_outbound(
            mut self,
            outbound: Arc<dyn moltis_channels::ChannelOutbound>,
        ) -> Self {
    ...
}

        fn with_channel_stream_outbound(
            mut self,
            outbound: Arc<dyn moltis_channels::ChannelStreamOutbound>,
        ) -> Self {
    ...
}
    }

    #[async_trait]
    impl ChatRuntime for MockChatRuntime {
        async fn broadcast(&self, _topic: &str, _payload: Value) {
        async fn push_channel_reply(
            &self,
            session_key: &str,
            target: moltis_channels::ChannelReplyTarget,
        ) {
    ...
}

        async fn drain_channel_replies(
            &self,
            session_key: &str,
        ) -> Vec<moltis_channels::ChannelReplyTarget> {
    ...
}

        async fn peek_channel_replies(
            &self,
            session_key: &str,
        ) -> Vec<moltis_channels::ChannelReplyTarget> {
    ...
}

        async fn push_channel_status_log(&self, session_key: &str, message: String) {
    ...
}

        async fn drain_channel_status_log(&self, session_key: &str) -> Vec<String> {
    ...
}

        async fn set_run_error(&self, _run_id: &str, _error: String) {
    ...
}

    fn mock_runtime() -> Arc<dyn ChatRuntime> {
    ...
}

    struct MockExecTool {
    ...
}

    #[test]
    fn truncate_at_char_boundary_handles_multibyte_boundary() {
    ...
}

    #[test]
    fn session_token_usage_prefers_request_fields_for_current_context() {
    ...
}

    #[test]
    fn session_token_usage_falls_back_to_legacy_turn_fields() {
    ...
}

    #[test]
    fn assistant_message_is_visible_for_reasoning_only_messages() {
    ...
}

    #[test]
    fn assistant_message_is_not_visible_when_content_and_reasoning_are_blank() {
    ...
}

    #[test]
    fn estimate_text_tokens_uses_non_empty_floor_and_byte_ratio() {
    ...
}

    #[test]
    fn parse_explicit_shell_command_extracts_command_text() {
    ...
}

    #[test]
    fn parse_explicit_shell_command_rejects_non_command_inputs() {
    ...
}

    #[test]
    fn prompt_now_for_timezone_returns_non_empty_string() {
    ...
}

    #[test]
    fn prompt_today_for_timezone_returns_non_empty_string() {
    ...
}

    #[test]
    fn server_prompt_timezone_prefers_configured_value() {
    ...
}

    #[test]
    fn server_prompt_timezone_defaults_to_server_local() {
    ...
}

    fn make_session_entry_with_binding(binding: Option<String>) -> SessionEntry {
    ...
}

    #[test]
    fn resolve_channel_runtime_context_sets_heartbeat_surface() {
    ...
}

    #[test]
    fn resolve_channel_runtime_context_extracts_channel_binding() {
    ...
}

    #[test]
    fn resolve_channel_runtime_context_falls_back_to_web_when_unbound() {
    ...
}

    #[test]
    fn refresh_runtime_prompt_time_sets_host_time() {
    ...
}

    #[test]
    fn apply_request_runtime_context_uses_request_timezone() {
    ...
}

    #[test]
    fn apply_voice_reply_suffix_keeps_datetime_tail_at_end() {
    ...
}

    #[test]
    fn apply_voice_reply_suffix_noop_for_text_reply_mode() {
    ...
}

    #[test]
    fn format_tool_status_message_calc_uses_expression() {
    ...
}

    #[test]
    fn format_tool_status_message_calc_handles_missing_expression() {
    ...
}

    #[test]
    fn prompt_sandbox_no_network_state_uses_config_for_docker() {
    ...
}

    #[test]
    fn prompt_sandbox_no_network_state_omits_unsupported_backends() {
    ...
}

    #[test]
    fn is_safe_user_audio_filename_allows_sanitized_names() {
    ...
}

    #[test]
    fn user_audio_path_from_params_builds_session_scoped_media_path() {
    ...
}

    #[test]
    fn user_audio_path_from_params_rejects_invalid_filename() {
    ...
}

    #[async_trait]
    impl moltis_channels::plugin::ChannelOutbound for MockChannelOutbound {
        async fn send_text(
            &self,
            _account_id: &str,
            _to: &str,
            _text: &str,
            _reply_to: Option<&str>,
        ) -> moltis_channels::Result<()> {

        async fn send_media(
            &self,
            _account_id: &str,
            _to: &str,
            _payload: &ReplyPayload,
            _reply_to: Option<&str>,
        ) -> moltis_channels::Result<()> {
    ...
}
    }

    #[async_trait]
    impl moltis_channels::plugin::ChannelOutbound for RecordingChannelOutbound {
        async fn send_text(
            &self,
            _account_id: &str,
            _to: &str,
            _text: &str,
            _reply_to: Option<&str>,
        ) -> moltis_channels::Result<()> {

        async fn send_media(
            &self,
            _account_id: &str,
            _to: &str,
            _payload: &ReplyPayload,
            _reply_to: Option<&str>,
        ) -> moltis_channels::Result<()> {
    ...
}

        async fn send_text_with_suffix(
            &self,
            _account_id: &str,
            _to: &str,
            _text: &str,
            _suffix_html: &str,
            _reply_to: Option<&str>,
        ) -> moltis_channels::Result<()> {
    ...
}

        async fn send_html(
            &self,
            _account_id: &str,
            _to: &str,
            html: &str,
            _reply_to: Option<&str>,
        ) -> moltis_channels::Result<()> {
    ...
}
    }

    #[async_trait]
    impl moltis_channels::plugin::ChannelStreamOutbound for MockChannelStreamOutbound {
        async fn send_stream(
            &self,
            _account_id: &str,
            _to: &str,
            reply_to: Option<&str>,
            mut stream: moltis_channels::StreamReceiver,
        ) -> moltis_channels::Result<()> {

        async fn is_stream_enabled(&self, _account_id: &str) -> bool {
    ...
}
    }

    async fn sqlite_pool() -> sqlx::SqlitePool {
    ...
}

    #[tokio::test]
    async fn deliver_channel_replies_waits_for_outbound_sends() {
    ...
}

    #[tokio::test]
    async fn deliver_channel_replies_skips_targets_already_streamed() {
    ...
}

    /// Regression test for #371: when `desired_reply_medium` is Voice but TTS
    /// is disabled, the text fallback must be skipped for targets that were
    /// already streamed — otherwise two identical text messages are delivered.
    #[tokio::test]
    async fn deliver_channel_replies_voice_no_tts_skips_streamed_text_fallback() {
    ...
}

    /// Regression test for #371: Telegram + Voice + NoTTS + streamed + logbook
    /// present — the logbook follow-up must still be sent via `send_html` even
    /// though the text fallback is skipped.
    #[tokio::test]
    async fn deliver_channel_replies_voice_no_tts_streamed_sends_logbook() {
    ...
}

    /// Regression test for #371: non-Telegram (Discord) + Voice + NoTTS +
    /// streamed — the logbook follow-up must still be sent, and duplicate
    /// text must not be delivered.
    #[tokio::test]
    async fn deliver_channel_replies_voice_no_tts_streamed_non_telegram_sends_logbook() {
    ...
}

    #[tokio::test]
    async fn deliver_channel_replies_streamed_targets_get_logbook_follow_up() {
    ...
}

    #[tokio::test]
    async fn channel_stream_dispatcher_records_completed_targets() {
    ...
}

    #[tokio::test]
    async fn channel_stream_dispatcher_skips_failed_workers_from_dedupe() {
    ...
}

    #[tokio::test]
    async fn channel_stream_dispatcher_skips_stream_disabled_targets() {
    ...
}

    #[tokio::test]
    async fn channel_stream_dispatcher_no_deltas_do_not_dedup_targets() {
    ...
}

    /// Regression test for #173: voice reply medium must not suppress stream
    /// dedup. When a dispatcher successfully streams to a target, the target
    /// key must appear in the completed set regardless of `ReplyMedium`.
    #[tokio::test]
    async fn channel_stream_voice_dedup_excludes_streamed_targets() {
    ...
}

    #[tokio::test]
    async fn explicit_sh_bypasses_provider_and_executes_directly() {
    ...
}

    #[tokio::test]
    async fn auto_compact_uses_explicit_session_key_for_channel_sessions() {
    ...
}

    #[test]
    fn format_channel_retry_message_rounds_up_seconds() {
    ...
}

    #[test]
    fn format_channel_error_message_prefers_structured_fields() {
    ...
}

    #[test]
    fn next_stream_retry_delay_uses_retry_after_for_rate_limits() {
    ...
}

    #[test]
    fn next_stream_retry_delay_retries_transient_server_errors_once() {
    ...
}

    #[tokio::test]
    async fn ordered_runner_event_callback_stays_in_order_with_variable_processing_latency() {
    ...
}

    /// Build a bare session_locks map for testing the semaphore logic
    /// without constructing a full LiveChatService.
    fn make_session_locks() -> Arc<RwLock<HashMap<String, Arc<Semaphore>>>> {
    ...
}

    async fn get_or_create_semaphore(
        locks: &Arc<RwLock<HashMap<String, Arc<Semaphore>>>>,
        key: &str,
    ) -> Arc<Semaphore> {
    ...
}

    fn make_active_run_maps() -> (
        Arc<RwLock<HashMap<String, AbortHandle>>>,
        Arc<RwLock<HashMap<String, String>>>,
    ) {
    ...
}

    fn make_terminal_runs() -> Arc<RwLock<HashSet<String>>> {
    ...
}

    #[tokio::test]
    async fn same_session_runs_are_serialized() {
    ...
}

    #[tokio::test]
    async fn different_sessions_run_in_parallel() {
    ...
}

    #[tokio::test]
    async fn abort_releases_permit() {
    ...
}

    #[tokio::test]
    async fn abort_run_handle_resolves_run_from_session_key() {
    ...
}

    #[tokio::test]
    async fn abort_run_handle_by_run_id_clears_session_lookup() {
    ...
}

    #[tokio::test]
    async fn abort_run_handle_ignores_terminal_run() {
    ...
}

    #[tokio::test]
    async fn agent_timeout_cancels_slow_future() {
    ...
}

    #[tokio::test]
    async fn agent_timeout_zero_means_no_timeout() {
    ...
}

    // ── Message queue tests ──────────────────────────────────────────────

    fn make_message_queue() -> Arc<RwLock<HashMap<String, Vec<QueuedMessage>>>> {
    ...
}

    fn make_target(message_id: &str) -> Value {
    ...
}

    #[tokio::test]
    async fn queue_enqueue_and_drain() {
    ...
}

    #[tokio::test]
    async fn queue_collect_concatenates_texts() {
    ...
}

    #[tokio::test]
    async fn try_acquire_returns_err_when_held() {
    ...
}

    #[tokio::test]
    async fn try_acquire_succeeds_when_free() {
    ...
}

    #[tokio::test]
    async fn queue_drain_empty_is_noop() {
    ...
}

    #[tokio::test]
    async fn queue_drain_drops_permit_before_send() {
    ...
}

    #[tokio::test]
    async fn followup_drain_sends_only_first_and_requeues_rest() {
    ...
}

    #[tokio::test]
    async fn followup_drain_preserves_per_message_channel_targets() {
    ...
}

    #[tokio::test]
    async fn collect_drain_uses_last_message_channel_target() {
    ...
}

    #[test]
    fn message_queue_mode_default_is_followup() {
    ...
}

    #[test]
    fn message_queue_mode_deserializes_from_toml() {
    ...
}

    #[tokio::test]
    async fn cancel_queued_clears_session_queue() {
    ...
}

    #[tokio::test]
    async fn cancel_queued_returns_count() {
    ...
}

    #[tokio::test]
    async fn cancel_queued_noop_for_empty_queue() {
    ...
}

    #[test]
    fn effective_tool_policy_profile_and_config_merge() {
    ...
}

    #[test]
    fn runtime_filters_apply_policy_without_skill_tool_restrictions() {
    ...
}

    #[test]
    fn runtime_filters_do_not_hide_create_skill_when_skill_allows_only_web_fetch() {
    ...
}

    #[test]
    fn priority_models_pin_raw_model_ids_first() {
    ...
}

    #[test]
    fn priority_models_match_separator_variants() {
    ...
}

    #[test]
    fn models_without_priority_prefer_subscription_providers() {
    ...
}

    #[test]
    fn explicit_priority_still_overrides_subscription_preference() {
    ...
}

    #[test]
    fn allowed_models_filters_by_substring_match() {
    ...
}

    #[test]
    fn allowed_models_empty_shows_all() {
    ...
}

    #[test]
    fn allowed_models_case_insensitive() {
    ...
}

    #[test]
    fn allowed_models_match_separator_variants() {
    ...
}

    #[test]
    fn allowed_models_numeric_pattern_does_not_match_extended_variants() {
    ...
}

    #[test]
    fn allowed_models_numeric_pattern_matches_provider_prefixed_models() {
    ...
}

    #[test]
    fn allowed_models_does_not_filter_local_llm_or_ollama() {
    ...
}

    #[test]
    fn allowed_models_does_not_filter_ollama_when_provider_is_aliased() {
    ...
}

    #[tokio::test]
    async fn list_and_list_all_return_all_registered_models() {
    ...
}

    #[tokio::test]
    async fn list_includes_created_at_in_response() {
    ...
}

    #[tokio::test]
    async fn list_includes_ollama_when_provider_is_aliased() {
    ...
}

    #[test]
    fn provider_filter_is_normalized_and_ignores_empty() {
    ...
}

    #[test]
    fn provider_matches_filter_is_case_insensitive() {
    ...
}

    #[test]
    fn push_provider_model_groups_models_by_provider() {
    ...
}

    #[tokio::test]
    async fn list_all_includes_disabled_models_and_list_hides_them() {
    ...
}

    #[test]
    fn probe_rate_limit_detection_matches_copilot_429_pattern() {
    ...
}

    #[test]
    fn probe_rate_limit_backoff_doubles_and_caps() {
    ...
}

    #[tokio::test]
    async fn model_test_rejects_missing_model_id() {
    ...
}

    #[tokio::test]
    async fn model_test_rejects_unknown_model() {
    ...
}

    #[tokio::test]
    async fn model_test_unknown_model_includes_suggestion() {
    ...
}

    #[test]
    fn suggest_model_ids_prefers_provider_and_similarity() {
    ...
}

    #[tokio::test]
    async fn model_test_returns_error_when_provider_fails() {
    ...
}

    #[test]
    fn probe_parallel_per_provider_defaults_and_clamps() {
    ...
}

    // ── to_user_content tests ─────────────────────────────────────────

    #[test]
    fn to_user_content_text_only() {
    ...
}

    #[test]
    fn to_user_content_multimodal_with_image() {
    ...
}

    #[test]
    fn to_user_content_drops_invalid_data_uri() {
    ...
}

    // ── Logbook formatting tests ─────────────────────────────────────────

    #[test]
    fn format_logbook_html_empty_entries() {
    ...
}

    #[test]
    fn format_logbook_html_single_entry() {
    ...
}

    #[test]
    fn format_logbook_html_multiple_entries() {
    ...
}

    #[test]
    fn format_logbook_html_escapes_html_entities() {
    ...
}

    // ── Tool result formatting tests ────────────────────────────────────

    #[test]
    fn format_tool_result_exec_with_exit_code_and_stderr() {
    ...
}

    #[test]
    fn format_tool_result_exec_exit_code_no_stderr() {
    ...
}

    #[test]
    fn format_tool_result_exec_no_exit_code_uses_error() {
    ...
}

    #[test]
    fn format_tool_result_browser_error() {
    ...
}

    #[test]
    fn format_tool_result_no_error_fallback() {
    ...
}

    #[test]
    fn extract_location_from_show_map_result() {
    ...
}

    #[test]
    fn extract_location_without_label() {
    ...
}

    #[test]
    fn extract_location_missing_coords_returns_none() {
    ...
}

    #[test]
    fn resolve_agent_memory_target_path_maps_to_agent_workspace() {
    ...
}

    #[test]
    fn resolve_agent_memory_target_path_rejects_invalid_paths() {
    ...
}

    #[test]
    fn path_in_agent_memory_scope_is_isolated_per_agent() {
    ...
}

    // ── active_session_keys tests ───────────────────────────────────────

    #[tokio::test]
    async fn active_session_keys_empty_when_no_runs() {
    ...
}

    #[tokio::test]
    async fn active_session_keys_returns_running_sessions() {
    ...
}

    #[test]
    fn active_tool_call_serializes_with_camel_case() {
    ...
}

    #[tokio::test]
    async fn peek_returns_inactive_when_no_run() {
    ...
}

    #[tokio::test]
    async fn abort_clears_active_tool_calls() {
    ...
}

    #[tokio::test]
    async fn abort_waits_for_pending_tool_history_before_persisting_partial() {
    ...
}

    #[tokio::test]
    async fn abort_persists_partial_stream_and_followup_reuses_it() {
    ...
}

    #[tokio::test]
    async fn send_sync_persists_tool_call_assistant_frames_for_history_replay() {
    ...
}

    // ── effective_tool_mode tests ───────────────────────────────────────

    /// Provider stub for testing `effective_tool_mode()` with configurable
    /// `supports_tools` and `tool_mode` values.
    struct ToolModeTestProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for ToolModeTestProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        fn tool_mode(&self) -> Option<ToolMode> {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[Value],
        ) -> Result<moltis_agents::model::CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[test]
    fn effective_tool_mode_native_when_supported_and_auto() {
    ...
}

    #[test]
    fn effective_tool_mode_text_when_not_supported_and_auto() {
    ...
}

    #[test]
    fn effective_tool_mode_respects_explicit_native() {
    ...
}

    #[test]
    fn effective_tool_mode_respects_explicit_text() {
    ...
}

    #[test]
    fn effective_tool_mode_respects_explicit_off() {
    ...
}

    #[test]
    fn effective_tool_mode_auto_explicit_delegates_to_supports_tools() {
    ...
}
}
