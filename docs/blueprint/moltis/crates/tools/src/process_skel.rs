use std::sync::Arc;

#[cfg(feature = "metrics")]
use std::time::Instant;

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    tracing::{debug, info, warn},
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram, labels, tools as tools_metrics};

use moltis_agents::tool_registry::AgentTool;

use crate::{
    exec::ExecOpts,
    sandbox::{SandboxId, SandboxRouter},
};

/// Regex pattern for valid tmux session names: only `[a-zA-Z0-9_-]`.
fn is_valid_session_name(name: &str) -> bool {
    ...
}

/// Generate a short unique session name.
fn generate_session_name() -> String {
    ...
}

/// Actions supported by the process tool.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
enum ProcessAction {
    ...
}

/// Result returned from a process tool action.
#[derive(Debug, Clone, Serialize)]
struct ProcessResult {
    ...
}

impl ProcessResult {
    fn ok(session_name: Option<String>, output: Option<String>) -> Self {

    fn err(msg: impl Into<String>) -> Self {
    ...
}
}

/// Tool for managing interactive/TUI processes via tmux inside the sandbox.
///
/// The LLM can start long-running or interactive programs (htop, vim, etc.)
/// in named tmux sessions, poll their output, send keystrokes, paste text,
/// and kill them.
#[derive(Default)]
pub struct ProcessTool {
    ...
}

impl ProcessTool {
    pub fn new() -> Self {

    /// Attach a sandbox router for per-session dynamic sandbox resolution.
    pub fn with_sandbox_router(mut self, router: Arc<SandboxRouter>) -> Self {
    ...
}

    /// Run a tmux command inside the sandbox container.
    async fn run_tmux(
        &self,
        session_key: &str,
        tmux_args: &str,
        timeout_secs: u64,
    ) -> anyhow::Result<crate::exec::ExecResult> {
    ...
}

    /// Resolve the sandbox ID for a session key (for logging).
    fn sandbox_id_for(&self, session_key: &str) -> Option<SandboxId> {
    ...
}

    async fn handle_start(
        &self,
        session_key: &str,
        command: &str,
        session_name: Option<&str>,
    ) -> ProcessResult {
    ...
}

    async fn handle_poll(&self, session_key: &str, session_name: &str) -> ProcessResult {
    ...
}

    async fn handle_send_keys(
        &self,
        session_key: &str,
        session_name: &str,
        keys: &str,
    ) -> ProcessResult {
    ...
}

    async fn handle_paste(
        &self,
        session_key: &str,
        session_name: &str,
        text: &str,
    ) -> ProcessResult {
    ...
}

    async fn handle_kill(&self, session_key: &str, session_name: &str) -> ProcessResult {
    ...
}

    async fn handle_list(&self, session_key: &str) -> ProcessResult {
    ...
}
}

#[async_trait]
impl AgentTool for ProcessTool {
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

    #[test]
    fn test_invalid_session_names() {
    ...
}

    #[test]
    fn test_session_name_too_long() {
    ...
}

    #[test]
    fn test_generate_session_name() {
    ...
}

    #[test]
    fn test_process_result_ok() {
    ...
}

    #[test]
    fn test_process_result_err() {
    ...
}

    #[test]
    fn test_process_result_serialization() {
    ...
}

    #[test]
    fn test_process_action_deserialize_start() {
    ...
}

    #[test]
    fn test_process_action_deserialize_start_no_name() {
    ...
}

    #[test]
    fn test_process_action_deserialize_start_empty_name() {
    ...
}

    #[test]
    fn test_process_action_deserialize_poll() {
    ...
}

    #[test]
    fn test_process_action_deserialize_send_keys() {
    ...
}

    #[test]
    fn test_process_action_deserialize_paste() {
    ...
}

    #[test]
    fn test_process_action_deserialize_kill() {
    ...
}

    #[test]
    fn test_process_action_deserialize_list() {
    ...
}

    #[test]
    fn test_process_action_invalid_action() {
    ...
}

    #[test]
    fn test_process_action_missing_required_field() {
    ...
}

    #[tokio::test]
    async fn test_process_tool_schema() {
    ...
}

    #[tokio::test]
    async fn test_process_tool_invalid_params() {
    ...
}

    #[tokio::test]
    async fn test_process_tool_invalid_session_name_on_poll() {
    ...
}

    #[tokio::test]
    async fn test_process_tool_invalid_session_name_on_send_keys() {
    ...
}

    #[tokio::test]
    async fn test_process_tool_invalid_session_name_on_paste() {
    ...
}

    #[tokio::test]
    async fn test_process_tool_invalid_session_name_on_kill() {
    ...
}

    #[tokio::test]
    async fn test_process_tool_list_no_sandbox() {
    ...
}

    #[tokio::test]
    async fn test_process_tool_start_without_command() {
    ...
}
}
