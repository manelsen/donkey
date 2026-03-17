//! Coqui TTS (local) provider.
//!
//! Coqui TTS is an open-source deep learning toolkit for Text-to-Speech.
//! Run the server: tts-server --model_name tts_models/en/ljspeech/tacotron2-DDC
//! Or use Docker: docker run -p 5002:5002 ghcr.io/coqui-ai/tts

use {
    crate::{
        config::CoquiTtsConfig,
        tts::{AudioFormat, AudioOutput, SynthesizeRequest, TtsProvider, Voice},
    },
    anyhow::{Result, anyhow},
    async_trait::async_trait,
    bytes::Bytes,
    reqwest::Client,
    serde::Deserialize,
};

const DEFAULT_ENDPOINT: &str = "http://localhost:5002";

/// Coqui TTS (local server) provider.
pub struct CoquiTts {
    ...
}

impl CoquiTts {
    /// Create a new Coqui TTS provider from config.
    #[must_use]
    pub fn new(config: &CoquiTtsConfig) -> Self {
}

#[async_trait]
impl TtsProvider for CoquiTts {
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

// Response type for speakers endpoint
#[derive(Deserialize)]
struct SpeakersResponse(Vec<String>);

#[cfg(test)]
mod tests {

    #[test]
    fn test_coqui_configured_with_model() {
    ...
}

    #[test]
    fn test_coqui_configured_with_custom_endpoint() {
    ...
}

    #[test]
    fn test_coqui_id_and_name() {
    ...
}
}
