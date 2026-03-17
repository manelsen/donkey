use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use tracing::debug;

use crate::types::Project;

fn now_ms() -> u64 {
    ...
}

/// Derive a human-friendly project label from a directory.
///
/// Resolution order:
/// 1. `Cargo.toml` package name
/// 2. `package.json` name
/// 3. Git remote origin name (last path segment)
/// 4. Directory name
pub fn derive_label(dir: &Path) -> String {
    ...
}

fn cargo_name(dir: &Path) -> Option<String> {
    ...
}

fn package_json_name(dir: &Path) -> Option<String> {
    ...
}

fn git_remote_name(dir: &Path) -> Option<String> {
    ...
}

/// Derive a slug-friendly ID from a directory path.
pub fn derive_id(dir: &Path) -> String {
    ...
}

/// Check if a directory is a git repository.
pub fn is_git_repo(dir: &Path) -> bool {
    ...
}

/// Detect a project from a directory. Returns `None` if directory doesn't exist.
pub fn detect_project(dir: &Path) -> Option<Project> {
    ...
}

/// Well-known parent directories where projects typically live.
const SCAN_PARENTS: &[&str] = &[
    "Projects",
    "Developer",
    "src",
    "code",
    "repos",
    "workspace",
    "dev",
    "git",
];

/// Return the immediate children of well-known project parent directories
/// under the user's home folder. Only existing directories are included.
pub fn default_scan_dirs() -> Vec<PathBuf> {
    ...
}

/// Scan well-known project parent directories under the given home path.
///
/// Extracted from [`default_scan_dirs`] so tests can pass a custom home
/// directory without mutating the process environment.
fn scan_dirs_from_home(home: &Path) -> Vec<PathBuf> {
    ...
}

/// Scan a list of directories and detect projects from git repos.
/// Returns new projects not already in `known_ids`.
pub fn auto_detect(dirs: &[&Path], known_ids: &[String]) -> Vec<Project> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_derive_label_package_json() {
    ...
}

    #[test]
    fn test_derive_label_fallback_to_dir_name() {
    ...
}

    #[test]
    fn test_is_git_repo() {
    ...
}

    #[test]
    fn test_detect_project() {
    ...
}

    #[test]
    fn test_derive_id() {
    ...
}

    #[test]
    fn test_default_scan_dirs_with_projects_folder() {
    ...
}

    #[test]
    fn test_default_scan_dirs_no_matching_parents() {
    ...
}
}
