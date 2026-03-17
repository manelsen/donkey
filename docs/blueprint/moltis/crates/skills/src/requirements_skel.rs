//! Binary requirement checking and dependency installation.

use std::path::Path;

use anyhow::{Context, bail};

use crate::types::{InstallKind, InstallSpec, SkillEligibility, SkillMetadata};

/// Resolve install command program + args from an install spec.
pub fn install_program_and_args(spec: &InstallSpec) -> anyhow::Result<(&'static str, Vec<&str>)> {
    ...
}

/// Render an install spec to a user-visible command preview.
pub fn install_command_preview(spec: &InstallSpec) -> anyhow::Result<String> {
    ...
}

/// Returns the current OS identifier used for platform filtering.
pub fn current_os() -> &'static str {
    ...
}

/// Check whether a binary exists in PATH.
pub fn check_bin(name: &str) -> bool {
    ...
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    ...
}

#[cfg(not(unix))]
fn is_executable(_path: &Path) -> bool {
    ...
}

/// Check all requirements for a skill and return eligibility info.
pub fn check_requirements(meta: &SkillMetadata) -> SkillEligibility {
    ...
}

/// Result of running an install command.
#[derive(Debug)]
pub struct InstallResult {
    ...
}

/// Run an install spec command (e.g. `brew install <formula>`).
pub async fn run_install(spec: &InstallSpec) -> anyhow::Result<InstallResult> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
