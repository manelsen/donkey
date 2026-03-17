//! Detection of an existing OpenClaw installation.

use std::path::{Path, PathBuf};

use tracing::{debug, info};

/// Result of scanning for an OpenClaw installation.
#[derive(Debug, Clone, serde::Serialize)]
pub struct OpenClawDetection {
    ...
}

/// Detect an OpenClaw installation.
///
/// Checks `OPENCLAW_HOME` env var first, then `~/.openclaw/`.
/// Returns `None` if the directory does not exist.
pub fn detect() -> Option<OpenClawDetection> {
    ...
}

/// Detect OpenClaw at a specific directory (for testing).
pub fn detect_at(home_dir: PathBuf) -> Option<OpenClawDetection> {
    ...
}

/// Resolve the OpenClaw home directory from env or default.
fn resolve_home_dir() -> Option<PathBuf> {
    ...
}

/// Resolve the workspace directory.
///
/// Resolution order:
/// 1. `OPENCLAW_PROFILE` env → `<home>/workspace-<profile>`
/// 2. `workspace` field from `openclaw.json` config (exact path)
/// 3. Remap: basename of configured workspace under `~/` (handles cross-machine paths like `/root/clawd` → `~/clawd`)
/// 4. Default `<home>/workspace` (if it exists)
/// 5. Well-known `~/clawd` directory (fallback for non-standard setups)
/// 6. Default `<home>/workspace` (even if absent, for logging)
fn resolve_workspace_dir(home: &Path) -> PathBuf {
    ...
}

/// Read the `agents.defaults.workspace` field from `openclaw.json`.
fn read_config_workspace(home: &Path) -> Option<String> {
    ...
}

/// Resolve the sessions directory for one agent, supporting both historical
/// and current OpenClaw layouts.
pub(crate) fn resolve_agent_sessions_dir(agent_dir: &Path) -> Option<PathBuf> {
    ...
}

/// Resolve auth-profiles path for one agent, supporting both historical and
/// current OpenClaw layouts.
pub(crate) fn resolve_agent_auth_profiles_path(agent_dir: &Path) -> Option<PathBuf> {
    ...
}

/// Scan `agents/` directory for agent IDs, session counts, and credentials.
fn scan_agents(home: &Path) -> (Vec<String>, usize, bool) {
    ...
}

/// Scan the config for unsupported channel names.
fn scan_unsupported_channels(home: &Path) -> Vec<String> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn detect_at_valid_dir() {
    ...
}

    #[test]
    fn detect_at_flat_agent_layout() {
    ...
}

    #[test]
    fn detect_at_missing_dir() {
    ...
}

    #[test]
    fn detect_at_empty_dir() {
    ...
}

    #[test]
    fn unsupported_channels_detected() {
    ...
}

    #[test]
    fn workspace_profile_resolution() {
    ...
}

    #[test]
    fn workspace_from_config() {
    ...
}

    #[test]
    fn workspace_from_config_remaps_cross_machine_path() {
    ...
}

    #[test]
    fn detect_resolves_workspace_from_config() {
    ...
}

    #[test]
    fn detect_workspace_files() {
    ...
}

    #[test]
    fn detect_no_workspace_files() {
    ...
}
}
