/// Local GGUF embedding provider using llama-cpp-2.
///
/// Provides offline embedding via small GGUF models (e.g. EmbeddingGemma-300M).
/// Requires the `local-embeddings` feature flag and CMake + C++ compiler at build time.
use std::path::PathBuf;

use {
    anyhow::{Context, Result, bail},
    async_trait::async_trait,
    llama_cpp_2::{
        context::params::LlamaContextParams,
        llama_backend::LlamaBackend,
        llama_batch::LlamaBatch,
        model::{LlamaModel, params::LlamaModelParams},
    },
    tokio::sync::Mutex,
    tracing::info,
};

use crate::embeddings::EmbeddingProvider;

/// Default model: EmbeddingGemma-300M quantized to Q8_0 (~300MB, 768 dims).
const DEFAULT_MODEL_FILENAME: &str = "embeddinggemma-300M-Q8_0.gguf";
const DEFAULT_MODEL_URL: &str = "https://huggingface.co/lmstudio-community/EmbeddingGemma-300M-GGUF/resolve/main/EmbeddingGemma-300M-Q8_0.gguf";
const DEFAULT_DIMS: usize = 768;

/// Wrapper around `LlamaBackend` that opts into `Send + Sync`.
///
/// `LlamaBackend` is `!Send` because `llama-cpp-2` doesn't mark its FFI
/// handle as thread-safe. In practice the backend is an opaque init token
/// with no mutable state after construction, so sharing across threads is
/// safe. Wrapping it in a newtype keeps the `unsafe` declaration localised
/// rather than applying `unsafe impl` to the entire provider struct.
struct SendSyncBackend(LlamaBackend);

// SAFETY: LlamaBackend is an immutable init handle with no thread-local state.
unsafe impl Send for SendSyncBackend {}
unsafe impl Sync for SendSyncBackend {
    /// Load a GGUF model from a specific path.
    pub fn new(model_path: PathBuf) -> Result<Self> {
    ...
}
    /// Ensure the default model exists in the cache directory, downloading if needed.
    pub async fn ensure_model(cache_dir: PathBuf) -> Result<PathBuf> {
    ...
}

    /// Default cache directory: `~/.moltis/models/`.
    pub fn default_cache_dir() -> PathBuf {
    ...
}
}

/// Embed a text using the given model and backend. Must be called from a sync context.
fn embed_sync(backend: &LlamaBackend, model: &LlamaModel, text: &str) -> Result<Vec<f32>> {
    ...
}

#[async_trait]
impl EmbeddingProvider for LocalGgufEmbeddingProvider {
    async fn embed(&self, text: &str) -> Result<Vec<f32>> {

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
}
