//! OpenAI Whisper STT provider implementation.
//!
//! Whisper is a general-purpose speech recognition model that handles
//! accents, background noise, and technical language well.

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

/// OpenAI API base URL.
const API_BASE: &str = "https://api.openai.com/v1";

/// Default Whisper model.
const DEFAULT_MODEL: &str = "whisper-1";

/// OpenAI Whisper STT provider.
#[derive(Clone)]
pub struct WhisperStt {
    ...
}

impl std::fmt::Debug for WhisperStt {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for WhisperStt {
    fn default() -> Self {
}

impl WhisperStt {
    /// Create a new Whisper STT provider.
    #[must_use]
    pub fn new(api_key: Option<Secret<String>>) -> Self {

    /// Create with custom model.
    #[must_use]
    pub fn with_model(api_key: Option<Secret<String>>, model: Option<String>) -> Self {
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
impl SttProvider for WhisperStt {
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
struct WhisperResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct WhisperWord {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
