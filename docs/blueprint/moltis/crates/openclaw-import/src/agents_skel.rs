//! Multi-agent extraction from OpenClaw installations.
//!
//! Reads the `agents.list` array from `openclaw.json` and resolves each
//! agent's workspace, identity metadata (theme), and a
//! sanitized Moltis agent ID.

use std::{
    collections::HashSet,
    path::{Path, PathBuf},
};

use {
    serde::{Deserialize, Serialize},
    tracing::{debug, info},
};

use crate::{detect::OpenClawDetection, identity, types::OpenClawConfig};

/// Per-agent data extracted from OpenClaw, to be consumed by the gateway.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ImportedAgent {
    ...
}

/// Collection of all agents extracted from an OpenClaw installation.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ImportedAgents {
    ...
}

/// Sanitize an OpenClaw agent ID into a valid Moltis agent ID.
///
/// - Lowercase, replace non-alphanumeric with `-`, collapse `--`, trim `-`
/// - Truncate to 50 characters
/// - Append `-2`, `-3` etc. if the ID collides with an existing one or `"main"`
pub fn sanitize_agent_id(raw: &str, existing_ids: &HashSet<String>) -> String {
    ...
}

/// Extract agent metadata from an OpenClaw installation.
///
/// Reads `openclaw.json` and resolves each agent's workspace, identity,
/// theme. The default agent gets `moltis_id = "main"`.
pub fn import_agents(detection: &OpenClawDetection) -> ImportedAgents {
    ...
}

/// Build `ImportedAgent` entries from the `agents.list` array in config.
fn extract_from_config_list(
    config: &OpenClawConfig,
    detection: &OpenClawDetection,
    used_ids: &mut HashSet<String>,
) -> Vec<ImportedAgent> {
    ...
}

/// Synthesize minimal `ImportedAgent` entries from detected agent directories
/// when no config list is available.
fn synthesize_from_detection(
    detection: &OpenClawDetection,
    used_ids: &mut HashSet<String>,
) -> Vec<ImportedAgent> {
    ...
}

/// Resolve the workspace directory for a specific agent.
///
/// Priority: configured workspace path → remap basename under `~/` →
/// agent's `agent/` subdir → detection workspace
fn resolve_agent_workspace(
    configured_workspace: Option<&str>,
    agent_id: &str,
    detection: &OpenClawDetection,
) -> Option<PathBuf> {
    ...
}

/// Check for a workspace within an agent's directory structure.
fn resolve_agent_dir_workspace(agent_dir: &Path) -> Option<PathBuf> {
    ...
}

/// Extract theme from an agent's workspace IDENTITY.md or config.
fn extract_agent_identity(workspace: &Option<PathBuf>, config: &OpenClawConfig) -> Option<String> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn sanitize_special_chars() {
    ...
}

    #[test]
    fn sanitize_collapses_dashes() {
    ...
}

    #[test]
    fn sanitize_trims_dashes() {
    ...
}

    #[test]
    fn sanitize_main_gets_suffix() {
    ...
}

    #[test]
    fn sanitize_collision_detection() {
    ...
}

    #[test]
    fn sanitize_multiple_collisions() {
    ...
}

    #[test]
    fn sanitize_empty_string() {
    ...
}

    #[test]
    fn sanitize_truncates_long_ids() {
    ...
}

    #[test]
    fn import_agents_single_default() {
    ...
}

    #[test]
    fn import_agents_multiple() {
    ...
}

    #[test]
    fn import_agents_with_identity() {
    ...
}

    #[test]
    fn import_agents_synthesizes_from_detection() {
    ...
}

    #[test]
    fn import_agents_no_config_no_agents() {
    ...
}
}
