use std::{
    fs,
    path::{Path, PathBuf},
};

use tracing::info;

use crate::{Result, types::ContextFile};

/// Names of context files to collect when walking the directory hierarchy.
const CONTEXT_FILE_NAMES: &[&str] = &["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md"];

/// Load all context files for a project directory.
///
/// Walks upward from `project_dir` to the filesystem root, collecting
/// `CLAUDE.md`, `CLAUDE.local.md`, and `AGENTS.md` at each level.
/// Also loads `.claude/rules/*.md` from `project_dir`.
///
/// Files are returned ordered outermost (root) first, innermost (project dir)
/// last, so that project-level files take highest priority when appended.
pub fn load_context_files(project_dir: &Path) -> Result<Vec<ContextFile>> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_load_claude_md() {
    ...
}

    #[test]
    fn test_load_agents_md() {
    ...
}

    #[test]
    fn test_load_multiple_context_files() {
    ...
}

    #[test]
    fn test_load_rules_dir() {
    ...
}

    #[test]
    fn test_ignores_empty_files() {
    ...
}
}
