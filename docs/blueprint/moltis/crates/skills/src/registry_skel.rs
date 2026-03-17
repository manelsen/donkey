use std::{collections::HashMap, path::Path};

use async_trait::async_trait;

use crate::{
    discover::SkillDiscoverer,
    parse,
    types::{SkillContent, SkillMetadata},
};

/// Registry for managing discovered and installed skills.
#[async_trait]
pub trait SkillRegistry: Send + Sync {
    /// List metadata for all available skills.
    async fn list_skills(&self) -> anyhow::Result<Vec<SkillMetadata>>;

    /// Load the full content of a skill by name.
    async fn load_skill(&self, name: &str) -> anyhow::Result<SkillContent>;

    /// Install a skill from a source (e.g. git URL).
    async fn install_skill(&self, source: &str) -> anyhow::Result<SkillMetadata>;

    /// Remove an installed skill by name.
    async fn remove_skill(&self, name: &str) -> anyhow::Result<()>;
}

/// In-memory registry backed by a discoverer.
pub struct InMemoryRegistry {
    ...
}

impl InMemoryRegistry {
    /// Create a new empty registry.
    pub fn new() -> Self {

    /// Populate the registry from a discoverer.
    pub async fn from_discoverer(discoverer: &dyn SkillDiscoverer) -> anyhow::Result<Self> {
    ...
}

    /// Add a skill directly (useful for testing).
    pub fn insert(&mut self, meta: SkillMetadata) {
    ...
}
}

impl Default for InMemoryRegistry {
    fn default() -> Self {
}

#[async_trait]
impl SkillRegistry for InMemoryRegistry {
    async fn list_skills(&self) -> anyhow::Result<Vec<SkillMetadata>> {

    async fn load_skill(&self, name: &str) -> anyhow::Result<SkillContent> {
    ...
}

    async fn install_skill(&self, _source: &str) -> anyhow::Result<SkillMetadata> {
    ...
}

    async fn remove_skill(&self, name: &str) -> anyhow::Result<()> {
    ...
}
}

/// Convenience: load a skill's full content given its path.
pub async fn load_skill_from_path(skill_dir: &Path) -> anyhow::Result<SkillContent> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
