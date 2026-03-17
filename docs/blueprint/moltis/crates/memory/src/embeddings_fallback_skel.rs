/// Fallback chain embedding provider: tries providers in order with circuit breaker.
use std::sync::atomic::{AtomicUsize, Ordering};
use std::{
    sync::Mutex,
    time::{Duration, Instant},
};

use {
    async_trait::async_trait,
    tracing::{info, warn},
};

use crate::embeddings::EmbeddingProvider;

/// Circuit breaker state for a single provider.
struct ProviderState {
    ...
}

impl ProviderState {
    fn new() -> Self {

    fn record_success(&self) {
    ...
}

    fn record_failure(&self) {
    ...
}

    fn is_tripped(&self) -> bool {
    ...
}
}

/// A provider entry in the fallback chain.
struct ChainEntry {
    ...
}

/// Tries embedding providers in order, skipping those with circuit breaker tripped.
pub struct FallbackEmbeddingProvider {
    ...
}

impl FallbackEmbeddingProvider {
    pub fn new(providers: Vec<(String, Box<dyn EmbeddingProvider>)>) -> Self {

    pub fn provider_names(&self) -> Vec<&str> {
    ...
}

    pub fn active_provider_name(&self) -> &str {
    ...
}

    fn active_entry(&self) -> Option<&ChainEntry> {
    ...
}
}

#[async_trait]
impl EmbeddingProvider for FallbackEmbeddingProvider {
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

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    struct SuccessProvider {
    ...
}

    #[async_trait]
    impl EmbeddingProvider for SuccessProvider {
        async fn embed(&self, _text: &str) -> anyhow::Result<Vec<f32>> {

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

    #[tokio::test]
    async fn test_fallback_first_succeeds() {
    ...
}

    #[tokio::test]
    async fn test_fallback_to_second() {
    ...
}

    #[tokio::test]
    async fn test_all_fail() {
    ...
}
}
