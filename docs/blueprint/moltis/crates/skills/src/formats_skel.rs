//! Repo format detection and adapters.
//!
//! Different AI coding tools use different layouts for their plugin/skill repos.
//! This module detects the format and normalizes repo contents into
//! `SkillMetadata` + body pairs that feed into the skills system.

use std::{
    collections::HashSet,
    path::{Component, Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::types::{SkillMetadata, SkillRequirements, SkillSource};

// ── Plugin format enum ──────────────────────────────────────────────────────

/// Detected format of a plugin/skill repository.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PluginFormat {
    ...
}

impl std::fmt::Display for PluginFormat {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

// ── Plugin skill entry ──────────────────────────────────────────────────────

/// A single skill entry scanned from a non-SKILL.md repo, with extra metadata
/// beyond what `SkillMetadata` carries.
#[derive(Debug, Clone, Serialize)]
pub struct PluginSkillEntry {
    ...
}

// ── Format adapter trait ────────────────────────────────────────────────────

/// A format adapter normalizes a non-SKILL.md repo into skill entries.
pub trait FormatAdapter: Send + Sync {
    /// Check whether the given repo directory matches this format.
    fn detect(&self, repo_dir: &Path) -> bool;

    /// Scan the repo and return enriched entries for each skill found.
    fn scan_skills(&self, repo_dir: &Path) -> anyhow::Result<Vec<PluginSkillEntry>>;
}

// ── Claude Code adapter ─────────────────────────────────────────────────────

/// Claude Code plugin metadata from `.claude-plugin/plugin.json`.
#[derive(Debug, Deserialize)]
struct ClaudePluginJson {
    ...
}

/// Claude Code marketplace metadata from `.claude-plugin/marketplace.json`.
#[derive(Debug, Deserialize)]
struct ClaudeMarketplaceJson {
    ...
}

#[derive(Debug, Deserialize)]
struct ClaudeMarketplacePlugin {
    ...
}

/// Author field can be a string or an object with `name` (and optionally `email`).
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum PluginAuthor {
    ...
}

impl PluginAuthor {
    fn name(&self) -> &str {
}

/// Adapter for Claude Code plugin repos.
pub struct ClaudeCodeAdapter;

impl ClaudeCodeAdapter {
    fn slug_to_display_name(slug: &str) -> String {

    /// Resolve `relative` against `base`, rejecting path traversal / absolute paths.
    fn resolve_relative_safe(base: &Path, relative: &str) -> Option<PathBuf> {
    ...
}

    fn scan_marketplace_manifest(
        &self,
        repo_dir: &Path,
        seen_names: &mut HashSet<String>,
    ) -> anyhow::Result<Vec<PluginSkillEntry>> {
    ...
}

    /// Scan a single plugin directory (one that has `.claude-plugin/plugin.json`).
    /// `repo_root` is the top-level repo directory; `source_file` paths are
    /// computed relative to it so that GitHub URLs work for marketplace repos.
    fn scan_single_plugin(
        &self,
        plugin_dir: &Path,
        repo_root: &Path,
    ) -> anyhow::Result<Vec<PluginSkillEntry>> {
    ...
}
}

impl FormatAdapter for ClaudeCodeAdapter {
    fn detect(&self, repo_dir: &Path) -> bool {

    fn scan_skills(&self, repo_dir: &Path) -> anyhow::Result<Vec<PluginSkillEntry>> {
    ...
}
}

// ── Format detection ────────────────────────────────────────────────────────

/// All known format adapters, in detection priority order.
fn adapters() -> Vec<(PluginFormat, Box<dyn FormatAdapter>)> {
    ...
}

/// Detect the format of a repository.
pub fn detect_format(repo_dir: &Path) -> PluginFormat {
    ...
}

/// Scan a repo using the detected format adapter.
/// Returns `None` for `Skill` format (caller should use existing SKILL.md scanning).
pub fn scan_with_adapter(
    repo_dir: &Path,
    format: PluginFormat,
) -> Option<anyhow::Result<Vec<PluginSkillEntry>>> {
    ...
}

/// Check if there's at least one SKILL.md in subdirectories.
fn has_skill_md_recursive(dir: &Path) -> bool {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_detect_skill_format_root() {
    ...
}

    #[test]
    fn test_detect_skill_format_subdir() {
    ...
}

    #[test]
    fn test_detect_claude_code_format() {
    ...
}

    #[test]
    fn test_detect_generic_fallback() {
    ...
}

    #[test]
    fn test_claude_code_adapter_scan() {
    ...
}

    #[test]
    fn test_claude_code_adapter_empty_dirs() {
    ...
}

    #[test]
    fn test_claude_code_adapter_skips_non_md() {
    ...
}

    #[test]
    fn test_detect_claude_code_marketplace_format() {
    ...
}

    #[test]
    fn test_claude_code_marketplace_scan() {
    ...
}

    #[test]
    fn test_claude_code_marketplace_scan_skills_array() {
    ...
}

    #[test]
    fn test_scan_with_adapter_skill_returns_none() {
    ...
}

    #[test]
    fn test_scan_with_adapter_claude_code() {
    ...
}
}
