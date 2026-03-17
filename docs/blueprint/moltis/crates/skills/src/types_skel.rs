use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::formats::PluginFormat;

// ── Skills manifest ──────────────────────────────────────────────────────────

/// Top-level manifest tracking installed repos and per-skill enabled state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillsManifest {
    ...
}

impl Default for SkillsManifest {
    fn default() -> Self {
}

impl SkillsManifest {
    pub fn add_repo(&mut self, entry: RepoEntry) {

    pub fn remove_repo(&mut self, source: &str) {
    ...
}

    pub fn find_repo(&self, source: &str) -> Option<&RepoEntry> {
    ...
}

    pub fn find_repo_mut(&mut self, source: &str) -> Option<&mut RepoEntry> {
    ...
}

    pub fn set_skill_enabled(&mut self, source: &str, skill_name: &str, enabled: bool) -> bool {
    ...
}

    pub fn set_skill_trusted(&mut self, source: &str, skill_name: &str, trusted: bool) -> bool {
    ...
}
}

/// A single cloned repository with its discovered skills.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepoEntry {
    ...
}

/// Per-skill enabled state within a repo.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillState {
    ...
}

fn default_trusted() -> bool {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
}

// ── Skill metadata ───────────────────────────────────────────────────────────

/// Where a skill was discovered from.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SkillSource {
    ...
}

/// Lightweight metadata parsed from SKILL.md frontmatter.
/// Loaded at startup for all discovered skills (cheap).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillMetadata {
    ...
}

// ── Skill requirements ──────────────────────────────────────────────────────

/// Binary and tool requirements declared in SKILL.md frontmatter.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SkillRequirements {
    ...
}

/// How to install a missing binary dependency.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallSpec {
    ...
}

/// Install method kind.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InstallKind {
    ...
}

/// Result of checking whether a skill's requirements are met.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillEligibility {
    ...
}

/// Full skill content: metadata + markdown body.
/// Loaded on demand when a skill is activated.
#[derive(Debug, Clone)]
pub struct SkillContent {
    ...
}
