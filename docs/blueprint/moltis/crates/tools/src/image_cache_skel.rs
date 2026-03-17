//! On-demand Dockerfile-based tool image caching.
//!
//! Skills can declare a `dockerfile` field pointing to a Dockerfile in their
//! directory. When a skill with a Dockerfile is invoked, the image is built
//! (if not already cached) and used as the sandbox container image.
//!
//! Images are tagged as `moltis-cache/<skill-name>:<content-hash>` where
//! the hash is the first 12 hex chars of the SHA-256 of the Dockerfile contents.

use std::path::Path;

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    tracing::{debug, info},
};

use crate::{
    Result,
    error::{Context, Error},
};

/// Metadata about a cached tool image.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedImage {
    ...
}

/// Trait for building and managing cached tool images.
///
/// Trait-based so alternative backends (e.g. Apple Container) can provide
/// their own implementation.
#[async_trait]
pub trait ImageBuilder: Send + Sync {
    /// Ensure an image exists for the given skill. Builds from the Dockerfile
    /// if not already cached. Returns the full image tag.
    async fn ensure_image(
        &self,
        skill_name: &str,
        dockerfile: &Path,
        context: &Path,
    ) -> Result<String>;

    /// List all cached tool images.
    async fn list_cached(&self) -> Result<Vec<CachedImage>>;

    /// Remove a single cached image by tag.
    async fn remove_cached(&self, tag: &str) -> Result<()>;

    /// Remove all cached tool images.
    async fn prune_all(&self) -> Result<usize>;
}

/// Docker-based image builder using `docker build`.
pub struct DockerImageBuilder;

impl DockerImageBuilder {
    ...
}

impl Default for DockerImageBuilder {
    fn default() -> Self {
}

#[async_trait]
impl ImageBuilder for DockerImageBuilder {
    async fn ensure_image(
        &self,
        skill_name: &str,
        dockerfile: &Path,
        context: &Path,
    ) -> Result<String> {

    async fn list_cached(&self) -> Result<Vec<CachedImage>> {
    ...
}

    async fn remove_cached(&self, tag: &str) -> Result<()> {
    ...
}

    async fn prune_all(&self) -> Result<usize> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_image_tag_deterministic() {
    ...
}

    #[test]
    fn test_image_tag_different_content() {
    ...
}

    #[test]
    fn test_image_tag_different_skill() {
    ...
}

    #[test]
    fn test_cached_image_serde() {
    ...
}
}
