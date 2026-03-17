//! Google Cloud Speech-to-Text provider implementation.
//!
//! Google Cloud provides speech recognition with support for over 125 languages
//! and variants. This implementation uses the REST API with API key authentication.

use {
    anyhow::{Context, Result, anyhow},
    async_trait::async_trait,
    base64::Engine,
    reqwest::Client,
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
};

use super::{SttProvider, TranscribeRequest, Transcript, Word};

/// Google Cloud Speech-to-Text API base URL.
const API_BASE: &str = "https://speech.googleapis.com/v1/speech:recognize";

/// Google Cloud STT provider.
#[derive(Clone)]
pub struct GoogleStt {
    ...
}

impl std::fmt::Debug for GoogleStt {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for GoogleStt {
    fn default() -> Self {
}

impl GoogleStt {
    /// Create a new Google STT provider.
    #[must_use]
    pub fn new(api_key: Option<Secret<String>>) -> Self {

    /// Create with custom options.
    #[must_use]
    pub fn with_options(
        api_key: Option<Secret<String>>,
        language: Option<String>,
        model: Option<String>,
    ) -> Self {
    ...
}

    /// Get the API key, returning an error if not configured.
    fn get_api_key(&self) -> Result<&Secret<String>> {
    ...
}

    /// Map our AudioFormat to Google's encoding enum.
    fn encoding(format: crate::tts::AudioFormat) -> &'static str {
    ...
}
}

#[async_trait]
impl SttProvider for GoogleStt {
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

/// Parse Google's time format (e.g., "1.500s") to seconds as f32.
fn parse_google_time(time_str: &str) -> f32 {
    ...
}

// ── API Types ──────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct GoogleRequest {
    ...
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct GoogleRecognitionConfig {
    ...
}

#[derive(Debug, Serialize)]
struct GoogleAudio {
    ...
}

#[derive(Debug, Deserialize, Default)]
struct GoogleResponse {
    ...
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoogleResult {
    ...
}

#[derive(Debug, Deserialize)]
struct GoogleAlternative {
    ...
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoogleWord {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
