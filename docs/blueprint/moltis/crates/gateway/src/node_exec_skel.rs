//! Route command execution to a remote node via `node.invoke` with `system.run`.
//!
//! When `tools.exec.host = "node"`, the gateway forwards shell commands to a
//! connected headless node instead of executing them locally or in a sandbox.

use std::{collections::HashMap, sync::Arc, time::Duration};

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
};

use crate::state::GatewayState;

/// Result of a remote command execution on a node.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeExecResult {
    ...
}

/// Environment variables that are safe to forward to a remote node.
const SAFE_ENV_ALLOWLIST: &[&str] = &["TERM", "LANG", "COLORTERM", "NO_COLOR", "FORCE_COLOR"];

/// Environment variable prefixes that are safe to forward.
const SAFE_ENV_PREFIX_ALLOWLIST: &[&str] = &["LC_"];

/// Environment variable patterns that must NEVER be forwarded to a remote node.
const BLOCKED_ENV_PREFIXES: &[&str] = &[
    "DYLD_",
    "LD_",
    "NODE_OPTIONS",
    "PYTHON",
    "PERL",
    "RUBYOPT",
    "SHELLOPTS",
    "PS4",
    // Security-sensitive keys
    "MOLTIS_",
    "OPENAI_",
    "ANTHROPIC_",
    "AWS_",
    "GOOGLE_",
    "AZURE_",
];

/// Forward a shell command to a connected node for execution.
///
/// Uses `node.invoke` internally with `system.run` as the command.
/// Returns the stdout/stderr/exit_code from the remote execution.
pub async fn exec_on_node(
    state: &Arc<GatewayState>,
    node_id: &str,
    command: &str,
    timeout_secs: u64,
    cwd: Option<&str>,
    env: Option<&HashMap<String, String>>,
) -> anyhow::Result<NodeExecResult> {
    ...
}

/// Query a node for its available LLM providers via `system.providers`.
pub async fn query_node_providers(
    state: &Arc<GatewayState>,
    node_id: &str,
) -> anyhow::Result<Vec<crate::nodes::NodeProviderEntry>> {
    ...
}

/// Resolve a node identifier (id or display name) to a node_id.
pub async fn resolve_node_id(state: &Arc<GatewayState>, node_ref: &str) -> Option<String> {
    ...
}

/// Filter environment variables to the safe allowlist.
fn filter_env(env: &HashMap<String, String>) -> HashMap<String, String> {
    ...
}

fn is_safe_env(key: &str) -> bool {
    ...
}

fn parse_exec_result(value: &serde_json::Value) -> anyhow::Result<NodeExecResult> {
    ...
}

/// Bridge that implements [`moltis_tools::exec::NodeExecProvider`] by
/// delegating to [`exec_on_node`] / [`resolve_node_id`] with a shared
/// `GatewayState`.
pub struct GatewayNodeExecProvider {
    ...
}

impl GatewayNodeExecProvider {
    pub fn new(state: Arc<GatewayState>) -> Self {
}

#[async_trait]
impl moltis_tools::exec::NodeExecProvider for GatewayNodeExecProvider {
    async fn exec_on_node(
        &self,
        node_id: &str,
        command: &str,
        timeout_secs: u64,
        cwd: Option<&str>,
        env: Option<&HashMap<String, String>>,
    ) -> anyhow::Result<moltis_tools::exec::ExecResult> {

    async fn resolve_node_id(&self, node_ref: &str) -> Option<String> {
    ...
}
}

// ── Node info provider ──────────────────────────────────────────────────────

/// Convert a `NodeSession` into a serializable `NodeInfo`.
fn node_to_info(n: &crate::nodes::NodeSession) -> moltis_tools::nodes::NodeInfo {
    ...
}

/// Bridge that implements [`moltis_tools::nodes::NodeInfoProvider`] by
/// reading from the `NodeRegistry` and session metadata in `GatewayState`.
pub struct GatewayNodeInfoProvider {
    ...
}

impl GatewayNodeInfoProvider {
    pub fn new(state: Arc<GatewayState>) -> Self {
}

#[async_trait]
impl moltis_tools::nodes::NodeInfoProvider for GatewayNodeInfoProvider {
    async fn list_nodes(&self) -> Vec<moltis_tools::nodes::NodeInfo> {

    async fn describe_node(&self, node_ref: &str) -> Option<moltis_tools::nodes::NodeInfo> {
    ...
}

    async fn set_session_node(
        &self,
        session_key: &str,
        node_ref: Option<&str>,
    ) -> anyhow::Result<Option<String>> {
    ...
}

    async fn resolve_node_id(&self, node_ref: &str) -> Option<String> {
    ...
}
}

#[cfg(test)]
mod tests {

    #[test]
    fn parse_structured_result() {
    ...
}

    #[test]
    fn parse_error_result() {
    ...
}
}
