/// OpenAI embeddings provider using the `/v1/embeddings` endpoint.
use async_trait::async_trait;
use {
    secrecy::ExposeSecret,
    serde::{Deserialize, Serialize},
    sha2::{Digest, Sha256},
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram, labels, memory as mem_metrics};

use crate::embeddings::EmbeddingProvider;

pub struct OpenAiEmbeddingProvider {
    ...
}

fn compute_provider_key(base_url: &str, model: &str) -> String {
    ...
}

fn normalize_base_url(url: &str) -> String {
    ...
}

fn has_version_suffix(base_url: &str) -> bool {
    ...
}

fn embeddings_endpoint(base_url: &str) -> String {
    ...
}

impl OpenAiEmbeddingProvider {
    pub fn new(api_key: String) -> Self {

    pub fn with_model(mut self, model: String, dims: usize) -> Self {
    ...
}

    pub fn with_base_url(mut self, url: String) -> Self {
    ...
}
}

#[derive(Serialize)]
struct EmbeddingRequest {
    ...
}

#[derive(Deserialize)]
struct EmbeddingResponse {
    ...
}

#[derive(Deserialize)]
struct EmbeddingData {
    ...
}

#[async_trait]
impl EmbeddingProvider for OpenAiEmbeddingProvider {
    async fn embed(&self, text: &str) -> anyhow::Result<Vec<f32>> {

    async fn embed_batch(&self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
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

#[cfg(test)]
mod tests {

    #[test]
    fn endpoint_from_v1_base_appends_embeddings_once() {
    ...
}

    #[test]
    fn endpoint_from_custom_version_suffix_keeps_version() {
    ...
}

    #[test]
    fn endpoint_preserves_explicit_embeddings_url() {
    ...
}
}
