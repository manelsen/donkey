//! Sub-agent tool: lets the LLM delegate tasks to a child agent loop.

use std::{collections::HashSet, sync::Arc};

use {async_trait::async_trait, tracing::info};

use crate::{
    error::Error,
    params::{bool_param, str_param, u64_param},
};

use {
    moltis_agents::{
        AgentRunError,
        model::LlmProvider,
        runner::{RunnerEvent, run_agent_loop_with_context},
        tool_registry::{AgentTool, ToolRegistry},
    },
    moltis_config::schema::{AgentPreset, AgentsConfig},
    moltis_providers::ProviderRegistry,
    moltis_sessions::{metadata::SqliteSessionMetadata, store::SessionStore},
};

use crate::sessions_communicate::{
    SendToSessionFn, SessionAccessPolicy, SessionsHistoryTool, SessionsListTool, SessionsSendTool,
};

/// Maximum nesting depth for sub-agents (prevents infinite recursion).
const MAX_SPAWN_DEPTH: u64 = 3;

/// Tool parameter injected via `tool_context` to track nesting depth.
const SPAWN_DEPTH_KEY: &str = "_spawn_depth";

/// Minimal delegate-only toolset for coordinator-style sub-agents.
const DELEGATE_TOOLS: &[&str] = &[
    "spawn_agent",
    "sessions_list",
    "sessions_history",
    "sessions_send",
    "task_list",
];

/// A tool that spawns a sub-agent running its own agent loop.
///
/// The sub-agent executes synchronously (blocks until done) and its result
/// is returned as the tool output. Sub-agents get a filtered copy of the
/// parent's tool registry (without the `spawn_agent` tool itself) and a
/// focused system prompt.
/// Callback for emitting events from the sub-agent back to the parent UI.
pub type OnSpawnEvent = Arc<dyn Fn(RunnerEvent) + Send + Sync>;

/// Dependencies for building policy-aware session tools in sub-agents.
#[derive(Clone)]
pub struct SessionDeps {
    ...
}

pub struct SpawnAgentTool {
    ...
}

impl SpawnAgentTool {
    pub fn new(
        provider_registry: Arc<tokio::sync::RwLock<ProviderRegistry>>,
        default_provider: Arc<dyn LlmProvider>,
        tool_registry: Arc<ToolRegistry>,
    ) -> Self {

    /// Set an event callback so sub-agent activity is visible to the UI.
    pub fn with_on_event(mut self, on_event: OnSpawnEvent) -> Self {
    ...
}

    /// Attach agent preset config for `preset` lookups.
    pub fn with_agents_config(
        mut self,
        agents_config: Arc<tokio::sync::RwLock<AgentsConfig>>,
    ) -> Self {
    ...
}

    /// Provide session dependencies so sub-agents can get policy-aware session tools.
    pub fn with_session_deps(mut self, deps: SessionDeps) -> Self {
    ...
}

    fn emit(&self, event: RunnerEvent) {
    ...
}

    fn parse_tool_name_array(params: &serde_json::Value, key: &str) -> crate::Result<Vec<String>> {
    ...
}

    fn build_sub_tools(
        &self,
        allow_tools: &[String],
        deny_tools: &[String],
        delegate_only: bool,
    ) -> ToolRegistry {
    ...
}

    /// Apply reasoning_effort from the agent preset to the provider, if set.
    ///
    /// Returns the original provider if reasoning_effort is not configured or
    /// the provider doesn't support it. Warns when the preset overrides a
    /// reasoning effort already set via the model ID suffix.
    fn maybe_apply_reasoning_effort(
        provider: Arc<dyn LlmProvider>,
        preset: Option<&AgentPreset>,
    ) -> Arc<dyn LlmProvider> {
    ...
}

    async fn resolve_preset(
        &self,
        params: &serde_json::Value,
    ) -> crate::Result<(Option<String>, Option<AgentPreset>)> {
    ...
}
}

/// Resolve the memory directory for a preset based on its scope.
fn resolve_memory_dir(
    preset_name: &str,
    scope: &moltis_config::schema::MemoryScope,
) -> std::path::PathBuf {
    ...
}

/// Load the first N lines of MEMORY.md from the agent's memory directory.
/// Returns `None` if the file doesn't exist or is empty.
fn load_memory_context(
    preset_name: &str,
    config: &moltis_config::schema::PresetMemoryConfig,
) -> Option<String> {
    ...
}

/// Load memory content from a specific directory.
fn load_memory_from_dir(dir: &std::path::Path, max_lines: usize) -> Option<String> {
    ...
}

/// Build the system prompt for a sub-agent, incorporating preset customizations.
fn build_sub_agent_prompt(
    task: &str,
    context: &str,
    preset: Option<&AgentPreset>,
    preset_name: Option<&str>,
) -> String {
    ...
}

#[async_trait]
impl AgentTool for SpawnAgentTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    /// Mock provider that returns a fixed response.
    struct MockProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for MockProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> anyhow::Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    fn make_empty_provider_registry() -> Arc<tokio::sync::RwLock<ProviderRegistry>> {
    ...
}

    struct DummyNamedTool {
    ...
}

    #[async_trait]
    impl AgentTool for DummyNamedTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
    }

    fn registry_with_tools(names: &[&str]) -> Arc<ToolRegistry> {
    ...
}

    fn agents_config_with_presets(
        default_preset: Option<&str>,
        presets: &[(&str, AgentPreset)],
    ) -> Arc<tokio::sync::RwLock<AgentsConfig>> {
    ...
}

    #[tokio::test]
    async fn test_sub_agent_runs_and_returns_result() {
    ...
}

    #[tokio::test]
    async fn test_depth_limit_rejects() {
    ...
}

    #[tokio::test]
    async fn test_spawn_agent_excluded_from_sub_registry() {
    ...
}

    #[tokio::test]
    async fn test_context_passed_to_sub_agent() {
    ...
}

    #[tokio::test]
    async fn test_missing_task_parameter() {
    ...
}

    #[tokio::test]
    async fn test_build_sub_tools_applies_allow_and_deny() {
    ...
}

    #[tokio::test]
    async fn test_build_sub_tools_delegate_only_uses_delegate_set() {
    ...
}

    #[tokio::test]
    async fn test_resolve_preset_uses_explicit_name() {
    ...
}

    #[tokio::test]
    async fn test_resolve_preset_uses_default_when_missing() {
    ...
}

    #[tokio::test]
    async fn test_resolve_preset_errors_when_name_missing() {
    ...
}

    #[test]
    fn test_identity_injected_into_system_prompt() {
    ...
}

    #[test]
    fn test_no_identity_uses_default_prompt() {
    ...
}

    #[test]
    fn test_memory_injected_into_system_prompt() {
    ...
}

    #[test]
    fn test_load_memory_truncates() {
    ...
}

    #[test]
    fn test_load_memory_empty_returns_none() {
    ...
}

    #[test]
    fn test_load_memory_missing_file_returns_none() {
    ...
}

    #[tokio::test]
    async fn test_timeout_cancels_long_running_agent() {
    ...
}
}
