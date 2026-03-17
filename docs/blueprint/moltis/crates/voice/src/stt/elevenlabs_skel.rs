//! ElevenLabs Scribe STT provider implementation.
//!
//! ElevenLabs Scribe provides high-quality speech-to-text with support for
//! 90+ languages, word-level timestamps, and speaker diarization.

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

/// ElevenLabs API base URL.
const API_BASE: &str = "https://api.elevenlabs.io/v1";

/// Default model (Scribe v2 for best quality and 150ms latency).
const DEFAULT_MODEL: &str = "scribe_v2";

/// ElevenLabs Scribe STT provider.
#[derive(Clone)]
pub struct ElevenLabsStt {
    ...
}

impl std::fmt::Debug for ElevenLabsStt {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for ElevenLabsStt {
    fn default() -> Self {
}

impl ElevenLabsStt {
    /// Create a new ElevenLabs Scribe STT provider.
    #[must_use]
    pub fn new(api_key: Option<Secret<String>>) -> Self {

    /// Create with custom options.
    #[must_use]
    pub fn with_options(
        api_key: Option<Secret<String>>,
        model: Option<String>,
        language: Option<String>,
    ) -> Self {
    ...
}

    /// Create with custom base URL (for testing).
    #[allow(clippy::unwrap_used, clippy::expect_used)]
    #[cfg(test)]
    #[must_use]
    pub fn with_base_url(mut self, base_url: impl Into<String>) -> Self {
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
}

#[async_trait]
impl SttProvider for ElevenLabsStt {
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
struct ElevenLabsResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct ElevenLabsWord {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
