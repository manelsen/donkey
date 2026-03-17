//! Local Voxtral STT provider via vLLM server.
//!
//! Connects to a locally running vLLM server serving the Voxtral model.
//! The server exposes an OpenAI-compatible transcription endpoint.
//!
//! Setup:
//! ```bash
//! pip install "vllm[audio]"
//! vllm serve mistralai/Voxtral-Mini-3B-2507 \
//!   --tokenizer_mode mistral --config_format mistral --load_format mistral
//! ```

use {
    anyhow::{Context, Result, anyhow},
    async_trait::async_trait,
    reqwest::{
        Client,
        multipart::{Form, Part},
    },
    serde::Deserialize,
};

use {
    super::{SttProvider, TranscribeRequest, Transcript, Word},
    crate::tts::AudioFormat,
};

/// Default vLLM server endpoint.
const DEFAULT_ENDPOINT: &str = "http://localhost:8000";

/// Local Voxtral STT provider via vLLM.
#[derive(Clone, Debug)]
pub struct VoxtralLocalStt {
    ...
}

impl Default for VoxtralLocalStt {
    fn default() -> Self {
}

impl VoxtralLocalStt {
    /// Create a new local Voxtral STT provider with default settings.
    #[must_use]
    pub fn new() -> Self {

    /// Create with custom options.
    #[must_use]
    pub fn with_options(
        endpoint: Option<String>,
        model: Option<String>,
        language: Option<String>,
    ) -> Self {
    ...
}

    /// Check if the vLLM server is reachable.
    async fn check_server(&self) -> bool {
    ...
}

    /// Get file extension for audio format.
    fn file_extension(format: AudioFormat) -> &'static str {
    ...
}

    /// Get MIME type for audio format.
    fn mime_type(format: AudioFormat) -> &'static str {
    ...
}
}

#[async_trait]
impl SttProvider for VoxtralLocalStt {
    fn id(&self) -> &'static str {

    fn name(&self) -> &'static str {
    ...
}

    fn is_configured(&self) -> bool {
    ...
}

    async fn transcribe(&self, request: TranscribeRequest) -> Result<Transcript> {
    ...
}
}

// ── API Types (OpenAI-compatible) ──────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct VllmResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct VllmWord {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
