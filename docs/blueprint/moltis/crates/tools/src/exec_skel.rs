use std::{collections::HashMap, path::PathBuf, sync::Arc, time::Duration};

#[cfg(feature = "metrics")]
use std::time::Instant;

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    tokio::process::Command,
    tracing::{debug, info, warn},
};

use crate::{Result, error::Error};

#[cfg(feature = "metrics")]
use moltis_metrics::{
    counter, gauge, histogram, labels, sandbox as sandbox_metrics, tools as tools_metrics,
};

use moltis_agents::tool_registry::AgentTool;

/// Event describing a completed exec invocation, passed to the completion callback.
#[derive(Debug, Clone)]
pub struct ExecCompletionEvent {
    ...
}

/// Callback fired after every exec completion. Used to enqueue system events
/// and wake the heartbeat.
pub type ExecCompletionFn = Arc<dyn Fn(ExecCompletionEvent) + Send + Sync>;

use crate::{
    approval::{ApprovalAction, ApprovalDecision, ApprovalManager},
    sandbox::{NoSandbox, Sandbox, SandboxId, SandboxRouter},
};

const MAX_SANDBOX_RECOVERY_RETRIES: usize = 1;

/// Broadcaster that notifies connected clients about pending approval requests.
#[async_trait]
pub trait ApprovalBroadcaster: Send + Sync {
    async fn broadcast_request(&self, request_id: &str, command: &str) -> Result<()>;
}

/// Provider of environment variables to inject into sandbox execution.
/// Values are wrapped in `Secret` to prevent accidental logging.
#[async_trait]
pub trait EnvVarProvider: Send + Sync {
    ...
}

/// Provider that routes command execution to a remote node.
///
/// Implemented by the gateway crate to bridge `ExecTool` (in tools) with
/// `node_exec::exec_on_node` (in gateway) without a direct dependency.
#[async_trait]
pub trait NodeExecProvider: Send + Sync {
    /// Execute a shell command on a remote node.
    async fn exec_on_node(
        &self,
        node_id: &str,
        command: &str,
        timeout_secs: u64,
        cwd: Option<&str>,
        env: Option<&HashMap<String, String>>,
    ) -> anyhow::Result<ExecResult>;

    /// Resolve a node reference (id or display name) to a node_id.
    async fn resolve_node_id(&self, node_ref: &str) -> Option<String>;
}

/// Result of a shell command execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecResult {
    ...
}

/// Options controlling exec behavior.
#[derive(Debug, Clone)]
pub struct ExecOpts {
    ...
}

impl Default for ExecOpts {
    fn default() -> Self {
}

fn truncate_output_for_display(output: &mut String, max_output_bytes: usize) {
    ...
}

/// Execute a shell command with timeout and output limits.
#[tracing::instrument(skip(opts), fields(timeout_secs = opts.timeout.as_secs()))]
pub async fn exec_command(command: &str, opts: &ExecOpts) -> Result<ExecResult> {
    ...
}

/// The exec tool exposed to the agent tool registry.
pub struct ExecTool {
    ...
}

impl Default for ExecTool {
    fn default() -> Self {
}

impl ExecTool {
    /// Attach approval gating to this exec tool.
    pub fn with_approval(
        mut self,
        manager: Arc<ApprovalManager>,
        broadcaster: Arc<dyn ApprovalBroadcaster>,
    ) -> Self {

    /// Attach a sandbox backend and ID for sandboxed execution (legacy static mode).
    pub fn with_sandbox(mut self, sandbox: Arc<dyn Sandbox>, id: SandboxId) -> Self {
    ...
}

    /// Attach a sandbox router for per-session dynamic sandbox resolution.
    pub fn with_sandbox_router(mut self, router: Arc<SandboxRouter>) -> Self {
    ...
}

    /// Attach an environment variable provider for sandbox injection.
    pub fn with_env_provider(mut self, provider: Arc<dyn EnvVarProvider>) -> Self {
    ...
}

    /// Attach a callback that fires after every exec completion.
    pub fn with_completion_callback(mut self, cb: ExecCompletionFn) -> Self {
    ...
}

    /// Route command execution to a remote node instead of local/sandbox.
    pub fn with_node_provider(
        mut self,
        provider: Arc<dyn NodeExecProvider>,
        default_node: Option<String>,
    ) -> Self {
    ...
}

    /// Clean up sandbox resources. Call on session end.
    pub async fn cleanup(&self) -> Result<()> {
    ...
}
}

#[async_trait]
impl AgentTool for ExecTool {
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

/// Build a set of strings to redact for a given secret value:
/// the raw value, its base64 encoding, and its hex encoding.
fn redaction_needles(value: &str) -> Vec<String> {
    ...
}

fn is_container_not_running_exec_error(stderr: &str) -> bool {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    struct TestBroadcaster {
    ...
}

    impl TestBroadcaster {
        fn new() -> Self {
    }

    #[test]
    fn truncate_output_for_display_handles_multibyte_boundary() {
    ...
}

    #[async_trait]
    impl ApprovalBroadcaster for TestBroadcaster {
        async fn broadcast_request(&self, _request_id: &str, _command: &str) -> Result<()> {
    }

    #[tokio::test]
    async fn test_exec_echo() {
    ...
}

    #[tokio::test]
    async fn test_exec_stderr() {
    ...
}

    #[tokio::test]
    async fn test_exec_exit_code() {
    ...
}

    #[tokio::test]
    async fn test_exec_timeout() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_empty_working_dir() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_safe_command_no_approval_needed() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_approval_approved() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_approval_denied() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_with_sandbox() {
    ...
}

    struct RetryRecoverySandbox {
    ...
}

    impl RetryRecoverySandbox {
        fn new(cleanup_should_fail: bool, failures_before_success: usize) -> Self {
    }

    #[async_trait]
    impl Sandbox for RetryRecoverySandbox {
        fn backend_name(&self) -> &'static str {

        async fn ensure_ready(&self, _id: &SandboxId, _image_override: Option<&str>) -> Result<()> {
    ...
}

        async fn exec(
            &self,
            _id: &SandboxId,
            _command: &str,
            _opts: &ExecOpts,
        ) -> Result<ExecResult> {
    ...
}

        async fn cleanup(&self, _id: &SandboxId) -> Result<()> {
    ...
}
    }

    #[derive(Default)]
    struct CaptureWorkingDirSandbox {
    ...
}

    #[async_trait]
    impl Sandbox for CaptureWorkingDirSandbox {
        fn backend_name(&self) -> &'static str {

        async fn ensure_ready(&self, _id: &SandboxId, _image_override: Option<&str>) -> Result<()> {
    ...
}

        async fn exec(
            &self,
            _id: &SandboxId,
            _command: &str,
            opts: &ExecOpts,
        ) -> Result<ExecResult> {
    ...
}

        async fn cleanup(&self, _id: &SandboxId) -> Result<()> {
    ...
}
    }

    #[tokio::test]
    async fn test_exec_tool_retries_container_not_running_with_cleanup() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_retries_container_not_running_when_cleanup_fails() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_stops_after_max_container_retries() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_cleanup_no_sandbox() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_cleanup_with_sandbox() {
    ...
}

    struct TestEnvProvider;

    #[async_trait]
    impl EnvVarProvider for TestEnvProvider {
        async fn get_env_vars(&self) -> Vec<(String, secrecy::Secret<String>)> {
    }

    #[tokio::test]
    async fn test_exec_tool_with_env_provider() {
    ...
}

    #[tokio::test]
    async fn test_env_var_redaction_base64_exfiltration() {
    ...
}

    #[tokio::test]
    async fn test_env_var_redaction_hex_exfiltration() {
    ...
}

    #[tokio::test]
    async fn test_env_var_redaction_file_exfiltration() {
    ...
}

    #[test]
    fn test_redaction_needles() {
    ...
}

    #[test]
    fn test_is_container_not_running_exec_error() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_with_sandbox_router_off() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_with_sandbox_router_session_key() {
    ...
}

    /// Regression test: when SandboxMode=All (the default) but the backend is
    /// NoSandbox (no container runtime), the exec tool must NOT use
    /// /home/sandbox as the working directory.  It should fall back to the host
    /// data directory and execute successfully.
    #[tokio::test]
    async fn test_exec_tool_no_container_backend_with_sandbox_mode_all() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_sandbox_rewrites_host_absolute_working_dir() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_sandbox_resolves_relative_working_dir_under_home() {
    ...
}

    #[tokio::test]
    async fn test_exec_tool_sandbox_keeps_in_sandbox_absolute_working_dir() {
    ...
}

    #[tokio::test]
    async fn test_exec_command_bad_working_dir_error_message() {
    ...
}

    #[tokio::test]
    async fn test_completion_callback_fires() {
    ...
}

    #[tokio::test]
    async fn test_no_callback_by_default() {
    ...
}
}
