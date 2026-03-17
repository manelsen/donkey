//! Local LLM backend trait and implementations.
//!
//! Backends handle the actual model loading and inference.

use std::{
    pin::Pin,
    sync::atomic::{AtomicU64, Ordering},
};

use {anyhow::Result, async_trait::async_trait, tokio_stream::Stream};

use moltis_agents::model::{ChatMessage, CompletionResponse, StreamEvent};

use super::LocalLlmConfig;

static LOADED_LLAMA_MODEL_BYTES: AtomicU64 = AtomicU64::new(0);

/// Total bytes currently held by loaded llama.cpp model tensors.
#[must_use]
pub fn loaded_llama_model_bytes() -> u64 {
    ...
}

/// Types of local LLM backends.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BackendType {
    ...
}

impl BackendType {
    /// Human-readable name for this backend.
    #[must_use]
    pub fn display_name(&self) -> &'static str {

    /// Whether this backend is optimized for the current platform.
    #[must_use]
    pub fn is_native(&self) -> bool {
    ...
}
}

impl std::fmt::Display for BackendType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// Trait for local LLM inference backends.
#[async_trait]
pub trait LocalBackend: Send + Sync {
    /// Get the backend type.
    fn backend_type(&self) -> BackendType;

    /// Get the model ID.
    fn model_id(&self) -> &str;

    /// Get the context window size.
    fn context_window(&self) -> u32;

    /// Whether this backend supports grammar-constrained tool calling.
    fn supports_tools(&self) -> bool {
    ...
}

    /// Run completion (non-streaming).
    async fn complete(&self, messages: &[ChatMessage]) -> Result<CompletionResponse>;

    /// Run completion with tool schemas for grammar-constrained generation.
    async fn complete_with_tools(
        &self,
        messages: &[ChatMessage],
        _tools: &[serde_json::Value],
    ) -> Result<CompletionResponse> {
    ...
}

    /// Run streaming completion.
    fn stream<'a>(
        &'a self,
        messages: &'a [ChatMessage],
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + 'a>>;
}

/// Detect the best backend for the current system (ignoring model type).
#[must_use]
pub fn detect_best_backend() -> BackendType {
    ...
}

/// Detect the best backend for a specific model.
///
/// This checks:
/// 1. Legacy MLX models (mlx-* prefix) -> requires MLX backend
/// 2. Unified registry models with MLX support -> prefers MLX on Apple Silicon
/// 3. GGUF-only models -> uses GGUF backend
/// 4. Unknown models -> falls back to system detection
#[must_use]
pub fn detect_backend_for_model(model_id: &str) -> BackendType {
    ...
}

/// Get list of available backends on this system.
#[must_use]
pub fn available_backends() -> Vec<BackendType> {
    ...
}

/// How mlx-lm is installed on this system.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MlxInstallation {
    ...
}

/// Detect how mlx-lm is installed, if at all.
#[must_use]
pub fn detect_mlx_installation() -> Option<MlxInstallation> {
    ...
}

/// Check if MLX backend is available.
#[must_use]
pub fn is_mlx_available() -> bool {
    ...
}

/// Create a backend instance for the given type and config.
pub async fn create_backend(
    backend_type: BackendType,
    config: &LocalLlmConfig,
) -> Result<Box<dyn LocalBackend>> {
    ...
}

// ── GGUF Backend ─────────────────────────────────────────────────────────────

pub mod gguf {
    //! GGUF backend using llama-cpp-2.

    use std::{num::NonZeroU32, pin::Pin, sync::Arc};

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

    use moltis_agents::model::{ChatMessage, CompletionResponse, StreamEvent, ToolCall, Usage};

    use {
        super::{BackendType, LocalBackend, LocalLlmConfig},
        crate::local_llm::models::{
            self, LocalModelDef,
            chat_templates::{ChatTemplateHint, format_messages},
        },
    };

    use crate::local_gguf::tool_grammar;

    /// Wrapper around `LlamaBackend` that opts into `Send + Sync`.
    struct SendSyncBackend(LlamaBackend);

    // SAFETY: LlamaBackend is an immutable init handle with no thread-local state.
    #[allow(unsafe_code)]
    unsafe impl Send for SendSyncBackend {}
    #[allow(unsafe_code)]
    unsafe impl Sync for SendSyncBackend {
    /// GGUF backend implementation.
        fn new(model: LlamaModel) -> Self {
    ...
}

    impl Drop for GgufModelHandle {
        fn drop(&mut self) {
    }

    pub struct GgufBackend {
    ...
}

    impl GgufBackend {
        /// Load a GGUF backend from configuration.
        pub async fn from_config(config: &LocalLlmConfig) -> Result<Self> {

        /// Get the chat template hint for this model.
        fn chat_template(&self) -> ChatTemplateHint {
    ...
}

        /// Generate text synchronously.
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
    impl LocalBackend for GgufBackend {
        fn backend_type(&self) -> BackendType {

        fn model_id(&self) -> &str {
    ...
}

        fn context_window(&self) -> u32 {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(&self, messages: &[ChatMessage]) -> Result<CompletionResponse> {
    ...
}

        async fn complete_with_tools(
            &self,
            messages: &[ChatMessage],
            tools: &[serde_json::Value],
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream<'a>(
            &'a self,
            messages: &'a [ChatMessage],
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + 'a>> {
            let prompt = format_messages(messages, self.chat_template());
            let max_tokens = 4096u32;

            let backend = Arc::clone(&self.backend);
            let model = Arc::clone(&self.model);
            let context_size = self.context_size;
            let temperature = self.temperature;

            Box::pin(async_stream::stream! {
                let (tx, mut rx) = tokio::sync::mpsc::channel::<StreamEvent>(32);

                let handle = tokio::task::spawn_blocking(move || {
                    stream_generate_sync(
                        &backend.0,
                        &model,
                        &prompt,
                        max_tokens,
                        context_size,
                        temperature,
                        tx,
                    )
                });

                while let Some(event) = rx.recv().await {
                    let is_done = matches!(event, StreamEvent::Done(_) | StreamEvent::Error(_));
                    yield event;
                    if is_done {
                        break;
                    }
                }

                if let Err(e) = handle.await {
                    warn!("generation task error: {e}");
                }
            })
        }
    }

    /// Streaming generation in a blocking context.
    fn stream_generate_sync(
        backend: &LlamaBackend,
        model: &GgufModelHandle,
        prompt: &str,
        max_tokens: u32,
        context_size: u32,
        temperature: f32,
        tx: tokio::sync::mpsc::Sender<StreamEvent>,
    ) {
    ...
}
}

// ── MLX Backend ──────────────────────────────────────────────────────────────

pub mod mlx {
    //! MLX backend for Apple Silicon.
    //!
    //! Uses mlx-lm Python package via subprocess for inference.
    //! This provides native Apple Silicon optimization through MLX.

    use std::{
        io::{BufRead, BufReader},
        path::PathBuf,
        pin::Pin,
        process::{Command, Stdio},
    };

    use {
        anyhow::{Context, Result, bail},
        async_trait::async_trait,
        tokio_stream::Stream,
        tracing::{info, warn},
    };

    use moltis_agents::model::{ChatMessage, CompletionResponse, StreamEvent, Usage};

    use {
        super::{BackendType, LocalBackend, LocalLlmConfig},
        crate::local_llm::models::{
            LocalModelDef,
            chat_templates::{ChatTemplateHint, format_messages},
        },
    };

    // Import the models module for model lookup and download
    use crate::local_llm::models;

    /// MLX backend implementation.
    pub struct MlxBackend {
    ...
}

    impl MlxBackend {
        /// Create an MLX backend from configuration.
        pub async fn from_config(config: &LocalLlmConfig) -> Result<Self> {

        /// Get the chat template hint for this model.
        fn chat_template(&self) -> ChatTemplateHint {
    ...
}

        /// Generate text using mlx-lm.
        async fn generate(&self, prompt: &str, max_tokens: u32) -> Result<(String, u32, u32)> {
    ...
}
    }

    /// Generate text using mlx-lm based on installation method.
    fn generate_with_mlx(
        model_path: &str,
        prompt: &str,
        max_tokens: u32,
        temperature: f32,
        installation: super::MlxInstallation,
    ) -> Result<(String, u32, u32)> {
    ...
}

    /// Generate text using mlx-lm as a Python package.
    fn generate_with_python(
        model_path: &str,
        prompt: &str,
        max_tokens: u32,
        temperature: f32,
    ) -> Result<(String, u32, u32)> {
    ...
}

    /// Strip common chat template stop tokens from model output.
    pub(crate) fn strip_chat_template_tokens(text: &str) -> String {
    ...
}

    /// Generate text using mlx-lm CLI (Homebrew installation).
    fn generate_with_cli(
        model_path: &str,
        prompt: &str,
        max_tokens: u32,
        temperature: f32,
    ) -> Result<(String, u32, u32)> {
    ...
}

    #[async_trait]
    impl LocalBackend for MlxBackend {
        fn backend_type(&self) -> BackendType {

        fn model_id(&self) -> &str {
    ...
}

        fn context_window(&self) -> u32 {
    ...
}

        async fn complete(&self, messages: &[ChatMessage]) -> Result<CompletionResponse> {
    ...
}

        fn stream<'a>(
            &'a self,
            messages: &'a [ChatMessage],
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + 'a>> {
            let prompt = format_messages(messages, self.chat_template());
            let model_path = self.model_path.to_string_lossy().to_string();
            let temperature = self.temperature;
            let installation = self.installation;

            Box::pin(async_stream::stream! {
                // Use spawn_blocking for the streaming generation
                let (tx, mut rx) = tokio::sync::mpsc::channel::<StreamEvent>(32);

                let handle = tokio::task::spawn_blocking(move || {
                    stream_generate_mlx(&model_path, &prompt, 4096, temperature, installation, tx)
                });

                while let Some(event) = rx.recv().await {
                    let is_done = matches!(event, StreamEvent::Done(_) | StreamEvent::Error(_));
                    yield event;
                    if is_done {
                        break;
                    }
                }

                if let Err(e) = handle.await {
                    warn!("MLX generation task error: {e}");
                }
            })
        }
    }

    /// Streaming generation using mlx-lm.
    fn stream_generate_mlx(
        model_path: &str,
        prompt: &str,
        max_tokens: u32,
        temperature: f32,
        installation: super::MlxInstallation,
        tx: tokio::sync::mpsc::Sender<StreamEvent>,
    ) {
    ...
}

    /// Streaming generation using mlx-lm Python package.
    fn stream_generate_python(
        model_path: &str,
        prompt: &str,
        max_tokens: u32,
        temperature: f32,
        tx: &tokio::sync::mpsc::Sender<StreamEvent>,
    ) -> Result<(u32, u32)> {
    ...
}

    /// Streaming generation using mlx-lm CLI (Homebrew).
    ///
    /// Note: The CLI doesn't support true streaming output, so we collect all
    /// output, parse it with the response parser, and send the cleaned text.
    fn stream_generate_cli(
        model_path: &str,
        prompt: &str,
        max_tokens: u32,
        temperature: f32,
        tx: &tokio::sync::mpsc::Sender<StreamEvent>,
    ) -> Result<(u32, u32)> {
    ...
}

    /// Resolve an MLX model, downloading it if necessary.
    ///
    /// Checks both the unified and legacy registries, downloads the model
    /// to the local cache, and returns the path to the model directory.
    async fn resolve_mlx_model(
        config: &LocalLlmConfig,
    ) -> Result<(PathBuf, Option<&'static LocalModelDef>, u32)> {
    ...
}
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_detect_best_backend() {
    ...
}

    #[test]
    fn test_available_backends_includes_gguf() {
    ...
}

    // ── detect_backend_for_model tests ─────────────────────────────────────

    #[test]
    fn test_detect_backend_for_legacy_mlx_model() {
    ...
}

    #[test]
    fn test_detect_backend_for_legacy_mlx_qwen_model() {
    ...
}

    #[test]
    fn test_detect_backend_for_gguf_model_from_legacy_registry() {
    ...
}

    #[test]
    fn test_detect_backend_for_unified_registry_gguf_model() {
    ...
}

    #[test]
    fn test_detect_backend_for_unknown_model() {
    ...
}

    #[test]
    fn test_detect_backend_for_unified_model_with_mlx_support() {
    ...
}

    #[test]
    fn test_detect_mlx_installation_consistency() {
    ...
}

    #[test]
    fn test_mlx_installation_enum_values() {
    ...
}

    // ── strip_chat_template_tokens tests ──────────────────────────────────

    #[test]
    fn test_strip_im_end_at_end() {
    ...
}

    #[test]
    fn test_strip_eot_id_at_end() {
    ...
}

    #[test]
    fn test_strip_eos_token_at_end() {
    ...
}

    #[test]
    fn test_strip_phi_end_token() {
    ...
}

    #[test]
    fn test_strip_endoftext_token() {
    ...
}

    #[test]
    fn test_strip_mid_response_stop_token() {
    ...
}

    #[test]
    fn test_no_stop_tokens_unchanged() {
    ...
}

    #[test]
    fn test_strip_empty_string() {
    ...
}

    #[test]
    fn test_strip_only_stop_token() {
    ...
}

    #[test]
    fn test_strip_trailing_whitespace_after_token_removal() {
    ...
}
}
