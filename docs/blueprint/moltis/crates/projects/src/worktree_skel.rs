use std::path::{Path, PathBuf};

use {
    crate::{Error, Result},
    tokio::process::Command,
    tracing::{debug, warn},
};

// NOTE: This module intentionally shells out to `git` for worktree porcelain
// operations (`worktree add/remove/list`, branch delete) because these flows are
// not yet practical with stable in-process gitoxide APIs in this code path.

const WORKTREE_DIR: &str = ".moltis-worktrees";

/// Information about an active worktree.
#[derive(Debug, Clone)]
pub struct WorktreeInfo {
    ...
}

/// Manages git worktrees for session isolation.
pub struct WorktreeManager;

impl WorktreeManager {
    /// Create a new worktree for a session, branching from HEAD.
    pub async fn create(project_dir: &Path, session_id: &str) -> Result<PathBuf> {

    /// Create a worktree from an existing branch.
    pub async fn create_from_branch(
        project_dir: &Path,
        session_id: &str,
        branch: &str,
    ) -> Result<PathBuf> {
    ...
}

    /// Remove a worktree and clean up the branch.
    /// If the branch was pushed to a remote, only the worktree is removed.
    /// If not pushed, the branch is also deleted.
    pub async fn cleanup(project_dir: &Path, session_id: &str) -> Result<()> {
    ...
}

    /// List active worktrees for a project.
    pub async fn list(project_dir: &Path) -> Result<Vec<WorktreeInfo>> {
    ...
}

    /// Run the project's setup command in a worktree directory.
    ///
    /// Injects `MOLTIS_WORKSPACE_NAME` (session id) and `MOLTIS_ROOT_PATH`
    /// (project root) as environment variables.
    pub async fn run_setup(
        wt_dir: &Path,
        setup_command: &str,
        project_dir: &Path,
        session_id: &str,
    ) -> Result<()> {
    ...
}

    /// Run a teardown command in a worktree directory before cleanup.
    pub async fn run_teardown(
        wt_dir: &Path,
        teardown_command: &str,
        project_dir: &Path,
        session_id: &str,
    ) -> Result<()> {
    ...
}

    /// Check if a worktree has uncommitted changes.
    pub async fn has_uncommitted_changes(wt_dir: &Path) -> Result<bool> {
    ...
}

    /// Check if a worktree branch has unpushed commits.
    pub async fn has_unpushed_commits(wt_dir: &Path, branch: &str) -> Result<bool> {
    ...
}

    /// Resolve the default base branch for a project (main, master, develop, trunk).
    pub async fn resolve_base_branch(project_dir: &Path) -> Result<String> {
    ...
}

    /// Create a worktree from a specific base branch.
    pub async fn create_from_base(
        project_dir: &Path,
        session_id: &str,
        base_branch: &str,
    ) -> Result<PathBuf> {
    ...
}

    async fn ensure_git_repo(dir: &Path) -> Result<()> {
    ...
}

    async fn is_branch_pushed(project_dir: &Path, branch: &str) -> bool {
    ...
}
}

/// Copy `.moltis/` config directory from project root to a worktree, if it
/// exists in the project but not in the worktree.
pub fn copy_project_config(project_dir: &Path, wt_dir: &Path) -> Result<()> {
    ...
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_create_and_list_worktree() {
    ...
}

    #[tokio::test]
    async fn test_create_idempotent() {
    ...
}

    #[tokio::test]
    async fn test_cleanup_worktree() {
    ...
}

    #[tokio::test]
    async fn test_not_git_repo() {
    ...
}

    #[tokio::test]
    async fn test_run_setup_with_env_vars() {
    ...
}

    #[tokio::test]
    async fn test_run_teardown() {
    ...
}

    #[tokio::test]
    async fn test_copy_project_config() {
    ...
}

    #[tokio::test]
    async fn test_copy_project_config_skips_if_exists() {
    ...
}

    #[tokio::test]
    async fn test_has_uncommitted_changes() {
    ...
}

    #[tokio::test]
    async fn test_resolve_base_branch() {
    ...
}

    #[tokio::test]
    async fn test_create_from_base() {
    ...
}
}
