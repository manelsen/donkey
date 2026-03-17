//! HOOK.md metadata parsing.
//!
//! Hook metadata is stored as TOML frontmatter in `HOOK.md` files:
//! ```text
//! +++
//! name = "my-hook"
//! description = "What it does"
//! events = ["BeforeToolCall"]
//! command = "./handler.sh"
//! timeout = 5
//!
//! [requires]
//! os = ["darwin", "linux"]
//! bins = ["jq"]
//! env = ["SLACK_WEBHOOK_URL"]
//! +++
//!
//! # My Hook
//! Extended docs go here.
//! ```

use std::{collections::HashMap, path::Path};

use serde::{Deserialize, Serialize};

use moltis_common::hooks::HookEvent;

/// Requirements that must be met for a hook to be eligible.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HookRequirements {
    ...
}

/// Metadata parsed from a HOOK.md file's TOML frontmatter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HookMetadata {
    ...
}

fn default_timeout() -> u64 {
    ...
}

/// Full parsed hook including metadata and the body text.
#[derive(Debug, Clone)]
pub struct ParsedHook {
    ...
}

/// Parse a HOOK.md file content into metadata + body.
///
/// Expects TOML frontmatter delimited by `+++` lines.
pub fn parse_hook_md(content: &str, source_path: &Path) -> crate::Result<ParsedHook> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn parse_minimal_hook_md() {
    ...
}

    #[test]
    fn parse_missing_frontmatter_fails() {
    ...
}

    #[test]
    fn parse_unclosed_frontmatter_fails() {
    ...
}
}
