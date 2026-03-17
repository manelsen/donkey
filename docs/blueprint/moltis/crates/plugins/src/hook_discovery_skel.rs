//! Hook discovery from filesystem directories.
//!
//! Scans configured directories for hook definitions (`HOOK.md` files)
//! and produces [`ParsedHook`] entries.

use std::path::PathBuf;

use {async_trait::async_trait, tracing::warn};

use crate::hook_metadata::{ParsedHook, parse_hook_md};

/// Source of a discovered hook.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HookSource {
    ...
}

/// Discovers hooks from the filesystem.
#[async_trait]
pub trait HookDiscoverer: Send + Sync {
    /// Scan configured paths and return all discovered hooks.
    async fn discover(&self) -> crate::Result<Vec<(ParsedHook, HookSource)>>;
}

/// Filesystem-based hook discoverer. Scans directories in priority order.
pub struct FsHookDiscoverer {
    ...
}

impl FsHookDiscoverer {
    pub fn new(search_paths: Vec<(PathBuf, HookSource)>) -> Self {

    /// Build the default search paths for hook discovery.
    ///
    /// Workspace root is always the configured data directory.
    pub fn default_paths() -> Vec<(PathBuf, HookSource)> {
    ...
}
}

#[async_trait]
impl HookDiscoverer for FsHookDiscoverer {
    async fn discover(&self) -> crate::Result<Vec<(ParsedHook, HookSource)>> {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn discover_skips_missing_dirs() {
    ...
}

    #[tokio::test]
    async fn discover_skips_dirs_without_hook_md() {
    ...
}

    #[tokio::test]
    async fn discover_skips_invalid_frontmatter() {
    ...
}
}
