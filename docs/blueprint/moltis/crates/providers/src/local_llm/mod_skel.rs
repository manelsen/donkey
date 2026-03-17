//! Local LLM provider with pluggable backends.
//!
//! Supports multiple inference backends:
//! - GGUF (llama.cpp) - Cross-platform, CPU + GPU
//! - MLX - Apple Silicon optimized (macOS only)
//!
//! The provider automatically selects the best backend based on the platform
//! and available hardware.

pub mod backend;
pub mod models;
pub mod response_parser;
pub mod system_info;

use std::{path::PathBuf, pin::Pin};

use {
    anyhow::Result, async_trait::async_trait, tokio::sync::RwLock, tokio_stream::Stream,
    tracing::info,
};

use moltis_agents::model::{ChatMessage, CompletionResponse, LlmProvider, StreamEvent};

pub use {
    backend::{BackendType, LocalBackend},
    models::{LocalModelDef, ModelFormat},
};

/// Total bytes currently held by loaded llama.cpp tensors for local GGUF
/// backends. This is updated when models are loaded/unloaded.
#[must_use]
pub fn loaded_llama_model_bytes() -> u64 {
    ...
}

/// Configuration for the local LLM provider.
#[derive(Debug, Clone)]
pub struct LocalLlmConfig {
    ...
}

impl Default for LocalLlmConfig {
    fn default() -> Self {
}

/// Local LLM provider with lazy loading.
///
/// Automatically selects the best backend for the current platform and
/// loads the model on first use.
pub struct LocalLlmProvider {
    ...
}

impl LocalLlmProvider {
    /// Create a new lazy-loading local LLM provider.
    pub fn new(config: LocalLlmConfig) -> Self {

    /// Get the backend type that will be (or was) used.
    pub async fn backend_type(&self) -> BackendType {
    ...
}

    /// Ensure the backend is loaded.
    async fn ensure_loaded(&self) -> Result<()> {
    ...
}
}

#[async_trait]
impl LlmProvider for LocalLlmProvider {
    fn name(&self) -> &str {

    fn id(&self) -> &str {
    ...
}

    fn context_window(&self) -> u32 {
    ...
}

    fn supports_tools(&self) -> bool {
    ...
}

    async fn complete(
        &self,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
    ) -> Result<CompletionResponse> {
    ...
}

    fn stream(
        &self,
        messages: Vec<ChatMessage>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
}

/// Log system info and backend availability.
pub fn log_system_info() {
    ...
}

#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_backend_detection() {
    ...
}

    #[test]
    fn test_available_backends() {
    ...
}
}
