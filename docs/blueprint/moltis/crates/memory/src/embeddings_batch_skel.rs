/// Batch embedding support using OpenAI's `/v1/batches` API for 50% cost reduction.
///
/// When enabled and the number of texts exceeds `batch_threshold`, uploads a JSONL file
/// to the batch API, polls for completion, and downloads results. Falls back to sequential
/// embedding on failure or timeout.
use anyhow::Result;
use {
    async_trait::async_trait,
    secrecy::{ExposeSecret, Secret},
    serde::Deserialize,
    tracing::{debug, info, warn},
};

use crate::embeddings::EmbeddingProvider;

/// Wraps an existing `EmbeddingProvider` and optionally uses the batch API for large batches.
pub struct BatchEmbeddingProvider {
    ...
}

impl BatchEmbeddingProvider {
    pub fn new(
        inner: Box<dyn EmbeddingProvider>,
        api_key: Secret<String>,
        base_url: String,
        batch_threshold: usize,
    ) -> Self {

    /// Upload JSONL, create batch, poll until done, download results.
    async fn batch_embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
    ...
}
}

#[async_trait]
impl EmbeddingProvider for BatchEmbeddingProvider {
    async fn embed(&self, text: &str) -> Result<Vec<f32>> {

    async fn embed_batch(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
    ...
}

    fn model_name(&self) -> &str {
    ...
}

    fn dimensions(&self) -> usize {
    ...
}

    fn provider_key(&self) -> &str {
    ...
}
}

// ── API response types ──────────────────────────────────────────────────

#[derive(Deserialize)]
struct FileUploadResponse {
    ...
}

#[derive(Deserialize)]
struct BatchResponse {
    ...
}

#[derive(Deserialize)]
struct BatchResultEntry {
    ...
}

#[derive(Deserialize)]
struct BatchResultResponse {
    ...
}

#[derive(Deserialize)]
struct BatchEmbeddingBody {
    ...
}

#[derive(Deserialize)]
struct BatchEmbeddingData {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_below_threshold_uses_inner() {
    ...
}

    #[tokio::test]
    async fn test_single_embed_uses_inner() {
    ...
}
}
