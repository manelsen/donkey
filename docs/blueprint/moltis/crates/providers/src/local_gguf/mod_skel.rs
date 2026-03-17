//! Local GGUF LLM provider using llama-cpp-2.
//!
//! Provides offline LLM inference via quantized GGUF models. Supports automatic
//! model download from HuggingFace and system memory detection for model suggestions.
//!
//! Requires the `local-llm` feature flag and CMake + C++ compiler at build time.

pub mod chat_templates;
pub mod models;
pub mod system_info;
pub mod tool_grammar;

use std::{num::NonZeroU32, path::PathBuf, pin::Pin, sync::Arc, time::Instant};

use {
    anyhow::{Context, Result, bail},
    async_trait::async_trait,
    llama_cpp_2::{
        context::params::LlamaContextParams,
        llama_backend::LlamaBackend,
        llama_batch::LlamaBatch,
        model::{LlamaModel, params::LlamaModelParams},
        sampling::LlamaSampler,
        token::LlamaToken,
    },
    tokio::sync::Mutex,
    tokio_stream::Stream,
    tracing::{debug, info, warn},
};

#[cfg(feature = "metrics")]
use moltis_metrics::{gauge, histogram, labels, llm as llm_metrics};

use moltis_agents::model::{
    ChatMessage, CompletionResponse, LlmProvider, StreamEvent, ToolCall, Usage,
};

use {
    chat_templates::{ChatTemplateHint, format_messages},
    models::{GgufModelDef, find_model},
};

/// Wrapper around `LlamaBackend` that opts into `Send + Sync`.
///
/// `LlamaBackend` is `!Send` because `llama-cpp-2` doesn't mark its FFI
/// handle as thread-safe. In practice the backend is an opaque init token
/// with no mutable state after construction, so sharing across threads is
/// safe. Wrapping it in a newtype keeps the `unsafe` declaration localised.
struct SendSyncBackend(LlamaBackend);

// SAFETY: LlamaBackend is an immutable init handle with no thread-local state.
#[allow(unsafe_code)]
unsafe impl Send for SendSyncBackend {}
#[allow(unsafe_code)]
unsafe impl Sync for SendSyncBackend {
/// Configuration for the local GGUF provider.
#[derive(Debug, Clone)]
    /// Model ID from the registry, or custom model name.
    /// Direct path to a GGUF file (skips auto-download).
    /// Context size in tokens (default: from model definition or 8192).
    /// Number of layers to offload to GPU (0 = CPU only).
    /// Sampling temperature.
    /// Directory for caching downloaded models.
    fn default() -> Self {
    ...
}

/// Local GGUF LLM provider.
pub struct LocalGgufProvider {
    ...
}

impl LocalGgufProvider {
    /// Create a new provider with an already-loaded model.
    fn new_with_model(
        backend: LlamaBackend,
        model: LlamaModel,
        model_id: String,
        model_def: Option<&'static GgufModelDef>,
        context_size: u32,
        temperature: f32,
    ) -> Self {

    /// Load a provider from configuration.
    ///
    /// This will download the model if needed.
    pub async fn from_config(config: LocalGgufConfig) -> Result<Self> {
    ...
}

    /// Get the chat template hint for this model.
    fn chat_template(&self) -> ChatTemplateHint {
    ...
}

    /// Generate text synchronously (called from blocking context).
    ///
    /// When `tool_names` is non-empty, a lazy GBNF grammar sampler constrains
    /// the output to valid `tool_call` fenced blocks.
    fn generate_sync(
        &self,
        prompt: &str,
        max_tokens: u32,
        tool_names: &[&str],
    ) -> Result<(String, u32, u32)> {
    ...
}
}

/// Detokenize a sequence of tokens into a string.
fn detokenize(model: &LlamaModel, tokens: &[LlamaToken]) -> Result<String> {
    ...
}

#[async_trait]
impl LlmProvider for LocalGgufProvider {
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

/// Streaming generation in a blocking context.
fn stream_generate_sync(
    backend: &LlamaBackend,
    model: &Mutex<LlamaModel>,
    prompt: &str,
    max_tokens: u32,
    context_size: u32,
    temperature: f32,
    tx: tokio::sync::mpsc::Sender<StreamEvent>,
) {
    ...
}

/// Lazy-loading wrapper for LocalGgufProvider.
///
/// The actual model is loaded on first use (complete/stream call).
/// This allows registration at startup without blocking on model download.
pub struct LazyLocalGgufProvider {
    ...
}

impl LazyLocalGgufProvider {
    /// Create a new lazy provider with the given config.
    pub fn new(config: LocalGgufConfig) -> Self {

    /// Ensure the inner provider is loaded, loading it if necessary.
    async fn ensure_loaded(&self) -> Result<()> {
    ...
}
}

#[async_trait]
impl LlmProvider for LazyLocalGgufProvider {
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

/// Log system info and suggest models on startup.
pub fn log_system_info_and_suggestions() {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_chat_template_selection() {
    ...
}

    #[test]
    fn test_log_system_info_does_not_suggest_mlx_on_non_apple() {
    ...
}

    #[test]
    fn test_log_system_info_suggests_mlx_on_apple() {
    ...
}
}
