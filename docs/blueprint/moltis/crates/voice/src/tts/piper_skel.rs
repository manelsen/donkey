//! Piper TTS (local) provider.
//!
//! Piper is a fast, local neural text-to-speech system.
//! Install: pip install piper-tts
//! Or download pre-built binaries from: https://github.com/rhasspy/piper/releases

use {
    crate::{
        config::PiperTtsConfig,
        tts::{AudioFormat, AudioOutput, SynthesizeRequest, TtsProvider, Voice},
    },
    anyhow::{Result, anyhow},
    async_trait::async_trait,
    bytes::Bytes,
    std::process::Stdio,
    tokio::{io::AsyncWriteExt, process::Command},
};

/// Piper TTS (local) provider.
pub struct PiperTts {
    ...
}

impl PiperTts {
    /// Create a new Piper TTS provider from config.
    #[must_use]
    pub fn new(config: &PiperTtsConfig) -> Self {

    fn get_binary(&self) -> &str {
    ...
}

    fn expand_path(path: &str) -> String {
    ...
}
}

#[async_trait]
impl TtsProvider for PiperTts {
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

#[cfg(test)]
mod tests {

    #[test]
    fn test_piper_configured_with_model() {
    ...
}

    #[test]
    fn test_piper_id_and_name() {
    ...
}

    #[test]
    fn test_expand_path() {
    ...
}
}
