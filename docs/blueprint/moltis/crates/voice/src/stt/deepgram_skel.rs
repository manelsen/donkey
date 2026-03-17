//! Deepgram STT provider implementation.
//!
//! Deepgram provides fast and accurate speech-to-text with various
//! models optimized for different use cases (Nova-3 being the latest).

use {
    anyhow::{Context, Result, anyhow},
    async_trait::async_trait,
    reqwest::{Client, Url},
    secrecy::{ExposeSecret, Secret},
    serde::Deserialize,
};

use {
    super::{SttProvider, TranscribeRequest, Transcript, Word},
    crate::tts::AudioFormat,
};

/// Deepgram API base URL.
const API_BASE: &str = "https://api.deepgram.com/v1/listen";

/// Default Deepgram model.
const DEFAULT_MODEL: &str = "nova-3";

/// Deepgram STT provider.
#[derive(Clone)]
pub struct DeepgramStt {
    ...
}

impl std::fmt::Debug for DeepgramStt {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for DeepgramStt {
    fn default() -> Self {
}

impl DeepgramStt {
    /// Create a new Deepgram STT provider.
    #[must_use]
    pub fn new(api_key: Option<Secret<String>>) -> Self {

    /// Create with custom options.
    #[must_use]
    pub fn with_options(
        api_key: Option<Secret<String>>,
        model: Option<String>,
        language: Option<String>,
        smart_format: bool,
    ) -> Self {
    ...
}

    /// Get the API key, returning an error if not configured.
    fn get_api_key(&self) -> Result<&Secret<String>> {
    ...
}

    /// Get MIME type for audio format.
    fn content_type(format: AudioFormat) -> &'static str {
    ...
}
}

#[async_trait]
impl SttProvider for DeepgramStt {
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
struct DeepgramResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct DeepgramMetadata {
    ...
}

#[derive(Debug, Deserialize)]
struct DeepgramResults {
    ...
}

#[derive(Debug, Deserialize)]
struct DeepgramChannel {
    ...
}

#[derive(Debug, Deserialize)]
struct DeepgramAlternative {
    ...
}

#[derive(Debug, Deserialize)]
struct DeepgramWord {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
