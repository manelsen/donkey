use std::path::{Component, Path, PathBuf};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram, skills as skills_metrics};

use crate::{
    formats::{PluginFormat, detect_format, scan_with_adapter},
    manifest::ManifestStore,
    parse,
    types::{RepoEntry, SkillMetadata, SkillState},
};

/// Install a skill repo from GitHub into the target directory.
///
/// Downloads the repo to `install_dir/<owner>-<repo>/`, auto-detects its format
/// (SKILL.md, Claude Code `.claude-plugin/`, etc.), scans for skills using the
/// appropriate adapter, and records the repo + skills in the manifest.
pub async fn install_skill(source: &str, install_dir: &Path) -> anyhow::Result<Vec<SkillMetadata>> {
    ...
}

/// Remove a repo: delete directory and manifest entry.
pub async fn remove_repo(source: &str, install_dir: &Path) -> anyhow::Result<()> {
    ...
}

/// Install by fetching a tarball from GitHub's API.
async fn install_via_http(
    owner: &str,
    repo: &str,
    target: &Path,
) -> anyhow::Result<Option<String>> {
    ...
}

async fn fetch_latest_commit_sha(
    client: &reqwest::Client,
    owner: &str,
    repo: &str,
) -> Option<String> {
    ...
}

fn sanitize_archive_path(path: &Path) -> anyhow::Result<Option<PathBuf>> {
    ...
}

/// Recursively scan a cloned repo for SKILL.md files.
/// Returns (Vec<SkillMetadata>, Vec<SkillState>) — metadata for callers and
/// state entries for the manifest.
async fn scan_repo_skills(
    repo_dir: &Path,
    install_dir: &Path,
) -> anyhow::Result<(Vec<SkillMetadata>, Vec<SkillState>)> {
    ...
}

/// Parse `owner/repo` from a source string.
/// Accepts `owner/repo`, `https://github.com/owner/repo`, or with trailing slash/`.git`.
fn parse_source(source: &str) -> anyhow::Result<(String, String)> {
    ...
}

/// Get the default installation directory.
pub fn default_install_dir() -> anyhow::Result<PathBuf> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_parse_source_github_url() {
    ...
}

    #[test]
    fn test_parse_source_invalid() {
    ...
}

    #[test]
    fn test_sanitize_archive_path_rejects_parent_dir() {
    ...
}

    #[test]
    fn test_sanitize_archive_path_accepts_normal_path() {
    ...
}

    #[tokio::test]
    async fn test_scan_single_skill_repo() {
    ...
}

    #[test]
    fn test_detect_format_routes_claude_code() {
    ...
}

    #[tokio::test]
    async fn test_scan_multi_skill_repo() {
    ...
}
}
