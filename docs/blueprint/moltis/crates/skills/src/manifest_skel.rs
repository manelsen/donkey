use std::path::{Path, PathBuf};

use crate::types::SkillsManifest;

/// Persistent manifest storage with atomic writes.
pub struct ManifestStore {
    ...
}

impl ManifestStore {
    pub fn new(path: PathBuf) -> Self {

    /// Default manifest path: `~/.moltis/skills-manifest.json`.
    pub fn default_path() -> anyhow::Result<PathBuf> {
    ...
}

    /// Load manifest from disk, returning a default if missing.
    pub fn load(&self) -> anyhow::Result<SkillsManifest> {
    ...
}

    /// Save manifest atomically via temp file + rename.
    pub fn save(&self, manifest: &SkillsManifest) -> anyhow::Result<()> {
    ...
}

    pub fn path(&self) -> &Path {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_load_missing_returns_default() {
    ...
}

    #[test]
    fn test_save_and_load_roundtrip() {
    ...
}

    #[test]
    fn test_manifest_set_skill_enabled() {
    ...
}

    #[test]
    fn test_manifest_set_skill_trusted() {
    ...
}

    #[test]
    fn test_manifest_remove_repo() {
    ...
}
}
