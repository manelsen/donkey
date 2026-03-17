//! OpenAI TTS provider implementation.
//!
//! OpenAI offers text-to-speech with multiple voices and two quality tiers:
//! - tts-1: Optimized for real-time, lower latency
//! - tts-1-hd: Higher quality, slightly higher latency

use {
    anyhow::{Context, Result, anyhow},
    async_trait::async_trait,
    reqwest::Client,
    secrecy::{ExposeSecret, Secret},
    serde::Serialize,
};

use super::{AudioFormat, AudioOutput, SynthesizeRequest, TtsProvider, Voice};

/// OpenAI API base URL.
const API_BASE: &str = "https://api.openai.com/v1";

/// Default voice.
const DEFAULT_VOICE: &str = "alloy";

/// Default model (real-time optimized).
const DEFAULT_MODEL: &str = "tts-1";

/// Available OpenAI TTS voices.
const VOICES: &[(&str, &str)] = &[
    ("alloy", "Alloy - Neutral, balanced"),
    ("echo", "Echo - Warm, conversational"),
    ("fable", "Fable - Expressive, storytelling"),
    ("onyx", "Onyx - Deep, authoritative"),
    ("nova", "Nova - Friendly, upbeat"),
    ("shimmer", "Shimmer - Soft, gentle"),
];

/// OpenAI TTS provider.
#[derive(Clone)]
pub struct OpenAiTts {
    ...
}

impl std::fmt::Debug for OpenAiTts {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for OpenAiTts {
    fn default() -> Self {
}

impl OpenAiTts {
    /// Create a new OpenAI TTS provider.
    #[must_use]
    pub fn new(api_key: Option<Secret<String>>) -> Self {

    /// Create with custom default voice and model.
    #[must_use]
    pub fn with_defaults(
        api_key: Option<Secret<String>>,
        voice: Option<String>,
        model: Option<String>,
    ) -> Self {
    ...
}

    /// Get the API key, returning an error if not configured.
    fn get_api_key(&self) -> Result<&Secret<String>> {
    ...
}

    /// Map audio format to OpenAI response format.
    fn response_format(format: AudioFormat) -> &'static str {
    ...
}
}

#[async_trait]
impl TtsProvider for OpenAiTts {
    fn id(&self) -> &'static str {

    fn name(&self) -> &'static str {
    ...
}

    fn is_configured(&self) -> bool {
    ...
}

    async fn voices(&self) -> Result<Vec<Voice>> {
    ...
}

    async fn synthesize(&self, request: SynthesizeRequest) -> Result<AudioOutput> {
    ...
}
}

// ── API Types ──────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct TtsRequest<'a> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_response_format() {
    ...
}

    #[test]
    fn test_debug_redacts_api_key() {
    ...
}

    #[tokio::test]
    async fn test_voices_returns_all_voices() {
    ...
}

    #[tokio::test]
    async fn test_synthesize_without_api_key() {
    ...
}

    #[test]
    fn test_with_defaults() {
    ...
}

    #[test]
    fn test_tts_request_serialization() {
    ...
}
}
