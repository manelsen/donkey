//! ElevenLabs TTS provider implementation.
//!
//! ElevenLabs offers high-quality, low-latency text-to-speech with support
//! for voice cloning and multiple models. The Flash v2.5 model provides
//! the lowest latency (~75ms) for conversational AI applications.

use {
    anyhow::{Context, Result, anyhow},
    async_trait::async_trait,
    reqwest::Client,
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
    tracing::{debug, info, warn},
};

use super::{AudioFormat, AudioOutput, SynthesizeRequest, TtsProvider, Voice, contains_ssml};

/// ElevenLabs API base URL.
const API_BASE: &str = "https://api.elevenlabs.io/v1";

/// Default voice ID (Rachel - clear, professional female voice).
const DEFAULT_VOICE_ID: &str = "21m00Tcm4TlvDq8ikWAM";

/// Default model (Flash v2.5 for lowest latency).
const DEFAULT_MODEL: &str = "eleven_flash_v2_5";

/// ElevenLabs TTS provider.
#[derive(Clone)]
pub struct ElevenLabsTts {
    ...
}

impl std::fmt::Debug for ElevenLabsTts {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for ElevenLabsTts {
    fn default() -> Self {
}

impl ElevenLabsTts {
    /// Create a new ElevenLabs TTS provider.
    #[must_use]
    pub fn new(api_key: Option<Secret<String>>) -> Self {

    /// Create with custom default voice and model.
    #[must_use]
    pub fn with_defaults(
        api_key: Option<Secret<String>>,
        voice_id: Option<String>,
        model: Option<String>,
    ) -> Self {
    ...
}

    /// Get the API key, returning an error if not configured.
    fn get_api_key(&self) -> Result<&Secret<String>> {
    ...
}

    /// Map audio format to ElevenLabs output format parameter.
    fn output_format_param(format: AudioFormat) -> &'static str {
    ...
}
}

#[async_trait]
impl TtsProvider for ElevenLabsTts {
    fn id(&self) -> &'static str {

    fn name(&self) -> &'static str {
    ...
}

    fn is_configured(&self) -> bool {
    ...
}

    fn supports_ssml(&self) -> bool {
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

fn is_false(v: &bool) -> bool {
    ...
}

#[derive(Debug, Serialize)]
struct TtsRequest<'a> {
    ...
}

#[derive(Debug, Serialize)]
struct VoiceSettings {
    ...
}

#[derive(Debug, Deserialize)]
struct VoicesResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct ElevenLabsVoice {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_provider_metadata() {
    ...
}

    #[test]
    fn test_output_format_param() {
    ...
}

    #[test]
    fn test_debug_redacts_api_key() {
    ...
}

    #[tokio::test]
    async fn test_voices_request() {
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
    fn test_ssml_detection_enables_parsing() {
    ...
}

    #[test]
    fn test_no_ssml_skips_parsing_field() {
    ...
}
}
