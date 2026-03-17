//! One-time migration from separate plugins system to unified skills system.
//!
//! On startup, checks for `plugins-manifest.json` and migrates entries into
//! `skills-manifest.json`, moving directories from `installed-plugins/` to
//! `installed-skills/`. This is idempotent and non-fatal.

use std::path::Path;

use crate::manifest::ManifestStore;

/// Migrate plugins data into the unified skills system.
///
/// - Merges repos from `plugins-manifest.json` into `skills-manifest.json`
/// - Moves directories from `installed-plugins/` to `installed-skills/`
/// - Preserves all fields: `trusted`, `enabled`, `commit_sha`, `format`, `relative_path`
/// - Skips entries already in skills manifest (idempotent)
/// - Deletes old manifest + empty old dir after successful migration
///
/// Non-fatal: logs a warning if migration fails.
pub async fn migrate_plugins_to_skills(data_dir: &Path) {
    ...
}

async fn try_migrate(data_dir: &Path) -> anyhow::Result<()> {
    ...
}

async fn cleanup_old_files(plugins_manifest_path: &Path, data_dir: &Path) {
    ...
}

async fn copy_dir_recursive(src: &Path, dst: &Path) -> anyhow::Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    use super::*;

    #[tokio::test]
    async fn test_migration_moves_repos() {
    ...
}

    #[tokio::test]
    async fn test_migration_is_idempotent() {
    ...
}

    #[tokio::test]
    async fn test_migration_noop_when_no_plugins_manifest() {
    ...
}

    #[tokio::test]
    async fn test_migration_empty_manifest_cleans_up() {
    ...
}
}
