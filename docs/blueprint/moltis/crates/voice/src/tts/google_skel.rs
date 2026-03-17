//! Google Cloud Text-to-Speech provider.

use {
    crate::{
        config::GoogleTtsConfig,
        tts::{AudioFormat, AudioOutput, SynthesizeRequest, TtsProvider, Voice, contains_ssml},
    },
    anyhow::{Result, anyhow},
    async_trait::async_trait,
    bytes::Bytes,
    reqwest::Client,
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
};

/// Google Cloud Text-to-Speech provider.
pub struct GoogleTts {
    ...
}

impl GoogleTts {
    /// Create a new Google Cloud TTS provider from config.
    #[must_use]
    pub fn new(config: &GoogleTtsConfig) -> Self {
}

#[async_trait]
impl TtsProvider for GoogleTts {
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

// ── API request/response types ─────────────────────────────────────────────

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SynthesizeRequestBody {
    ...
}

#[derive(Serialize)]
struct SynthesisInput {
    ...
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct VoiceSelectionParams {
    ...
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AudioConfig {
    ...
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SynthesizeResponse {
    ...
}

#[derive(Deserialize)]
struct VoicesResponse {
    ...
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoogleVoice {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_google_tts_id_and_name() {
    ...
}

    #[test]
    fn language_prefix_extraction_handles_short_tags() {
    ...
}
}
