use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// A project represents a codebase directory that moltis can work with.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    ...
}

/// A context file loaded from a project directory hierarchy.
#[derive(Debug, Clone)]
pub struct ContextFile {
    ...
}

/// Aggregated context for a project: the project itself plus all loaded context files.
#[derive(Debug, Clone)]
pub struct ProjectContext {
    ...
}

impl ProjectContext {
    /// Build the combined context string suitable for system prompt injection.
    pub fn to_prompt_section(&self) -> String {
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_prompt_section_without_worktree() {
    ...
}

    #[test]
    fn test_prompt_section_with_worktree() {
    ...
}

    #[test]
    fn test_prompt_section_with_context_files() {
    ...
}
}
