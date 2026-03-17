//! Groq STT provider implementation.
//!
//! Groq provides a Whisper-compatible API endpoint with various
//! Whisper models optimized for their LPU inference hardware.

use {
    anyhow::{Context, Result, anyhow},
    async_trait::async_trait,
    reqwest::{
        Client,
        multipart::{Form, Part},
    },
    secrecy::{ExposeSecret, Secret},
    serde::Deserialize,
};

use {
    super::{SttProvider, TranscribeRequest, Transcript, Word},
    crate::tts::AudioFormat,
};

/// Groq API base URL.
const API_BASE: &str = "https://api.groq.com/openai/v1";

/// Default Groq Whisper model.
const DEFAULT_MODEL: &str = "whisper-large-v3-turbo";

/// Groq STT provider using Whisper-compatible API.
#[derive(Clone)]
pub struct GroqStt {
    ...
}

impl std::fmt::Debug for GroqStt {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for GroqStt {
    fn default() -> Self {
}

impl GroqStt {
    /// Create a new Groq STT provider.
    #[must_use]
    pub fn new(api_key: Option<Secret<String>>) -> Self {

    /// Create with custom model and language.
    #[must_use]
    pub fn with_options(
        api_key: Option<Secret<String>>,
        model: Option<String>,
        language: Option<String>,
    ) -> Self {
    ...
}

    /// Get the API key, returning an error if not configured.
    fn get_api_key(&self) -> Result<&Secret<String>> {
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
impl SttProvider for GroqStt {
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

// ── API Types ──────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct GroqResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct GroqWord {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
