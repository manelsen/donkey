//! Markdown-based agent definitions with YAML frontmatter.
//!
//! Scans `~/.moltis/agents/` and `.moltis/agents/` for `.md` files,
//! parsing YAML frontmatter into [`AgentPreset`] fields and using the
//! body as `system_prompt_suffix`.
//!
//! # Format
//!
//! ```markdown
//! ---
//! name: code-reviewer
//! tools: Read, Grep, Glob
//! model: sonnet
//! ---
//! System prompt body here...
//! ```

use std::{collections::HashMap, path::Path};

use tracing::{debug, warn};

use crate::schema::{AgentIdentity, AgentPreset, PresetToolPolicy};

/// Frontmatter fields parsed from the YAML block.
#[derive(Debug, Default, serde::Deserialize)]
#[serde(default)]
struct AgentFrontmatter {
    ...
}

/// Parse a markdown agent definition file into a preset name and config.
///
/// Returns `(preset_name, AgentPreset)` or an error if parsing fails.
pub fn parse_agent_md(content: &str) -> anyhow::Result<(String, AgentPreset)> {
    ...
}

/// Split frontmatter (between `---` delimiters) from the body.
fn split_frontmatter(content: &str) -> anyhow::Result<(String, String)> {
    ...
}

/// Discover agent definition files from standard directories.
///
/// Scans `~/.moltis/agents/` (user-global) then `.moltis/agents/` (project-local).
/// Project-local files override user-global ones with the same name.
pub fn discover_agent_defs() -> HashMap<String, AgentPreset> {
    ...
}

/// Merge discovered agent definitions into the config's preset map.
///
/// TOML presets take precedence — markdown defs are only inserted
/// for names that don't already exist.
pub fn merge_agent_defs(
    presets: &mut HashMap<String, AgentPreset>,
    defs: HashMap<String, AgentPreset>,
) {
    ...
}

fn load_defs_from_dir(dir: &Path, defs: &mut HashMap<String, AgentPreset>) {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_parse_full_frontmatter() {
    ...
}

    #[test]
    fn test_body_becomes_system_prompt_suffix() {
    ...
}

    #[test]
    fn test_empty_body() {
    ...
}

    #[test]
    fn test_missing_delimiters_error() {
    ...
}

    #[test]
    fn test_missing_closing_delimiter() {
    ...
}

    #[test]
    fn test_missing_name_error() {
    ...
}

    #[test]
    fn test_discover_from_directory() {
    ...
}

    #[test]
    fn test_merge_does_not_override_toml() {
    ...
}

    #[test]
    fn test_project_overrides_user() {
    ...
}
}
