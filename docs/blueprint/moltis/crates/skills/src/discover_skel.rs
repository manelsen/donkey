use std::path::{Path, PathBuf};

use async_trait::async_trait;

use crate::{
    formats::PluginFormat,
    manifest::ManifestStore,
    parse,
    types::{SkillMetadata, SkillSource},
};

/// Discovers skills from filesystem paths.
#[async_trait]
pub trait SkillDiscoverer: Send + Sync {
    /// Scan configured paths and return metadata for all discovered skills.
    async fn discover(&self) -> anyhow::Result<Vec<SkillMetadata>>;
}

/// Default filesystem-based skill discoverer.
pub struct FsSkillDiscoverer {
    ...
}

impl FsSkillDiscoverer {
    pub fn new(search_paths: Vec<(PathBuf, SkillSource)>) -> Self {

    /// Build the default search paths for skill discovery.
    ///
    /// Workspace root is always the configured data directory.
    pub fn default_paths() -> Vec<(PathBuf, SkillSource)> {
    ...
}
}

#[async_trait]
impl SkillDiscoverer for FsSkillDiscoverer {
    async fn discover(&self) -> anyhow::Result<Vec<SkillMetadata>> {
}

/// Scan one level deep for SKILL.md dirs (project/personal sources).
fn discover_flat(base_path: &Path, source: &SkillSource, skills: &mut Vec<SkillMetadata>) {
    ...
}

/// Discover enabled plugin skills using the plugins manifest.
/// Plugin skills don't have SKILL.md — they are normalized by format adapters.
/// This returns lightweight metadata from the manifest for prompt injection.
fn discover_plugins(install_dir: &Path, skills: &mut Vec<SkillMetadata>) {
    ...
}

/// Discover registry skills using the manifest for enabled filtering.
///
/// Handles both formats:
/// - `PluginFormat::Skill` → parse `SKILL.md` from disk for full metadata
/// - Other formats → create stub metadata with `SkillSource::Plugin` (prompt_gen
///   uses the path as-is instead of appending `/SKILL.md`)
fn discover_registry(install_dir: &Path, skills: &mut Vec<SkillMetadata>) {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_discover_skills_in_temp_dir() {
    ...
}

    #[tokio::test]
    async fn test_discover_skips_missing_dirs() {
    ...
}

    #[tokio::test]
    async fn test_discover_skips_dirs_without_skill_md() {
    ...
}

    #[tokio::test]
    async fn test_discover_skips_invalid_frontmatter() {
    ...
}

    #[tokio::test]
    async fn test_discover_registry_filters_disabled() {
    ...
}

    #[test]
    fn test_discover_registry_mixed_formats() {
    ...
}
}
