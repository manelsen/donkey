//! Speech-to-Text provider abstraction and implementations.

mod cli_utils;
mod deepgram;
mod elevenlabs;
mod google;
mod groq;
mod mistral;
mod sherpa_onnx;
mod voxtral_local;
mod whisper;
mod whisper_cli;

pub use {
    deepgram::DeepgramStt, elevenlabs::ElevenLabsStt, google::GoogleStt, groq::GroqStt,
    mistral::MistralStt, sherpa_onnx::SherpaOnnxStt, voxtral_local::VoxtralLocalStt,
    whisper::WhisperStt, whisper_cli::WhisperCliStt,
};

use {
    anyhow::Result,
    async_trait::async_trait,
    bytes::Bytes,
    serde::{Deserialize, Serialize},
};

use crate::tts::AudioFormat;

/// Request to transcribe audio to text.
#[derive(Debug, Clone)]
pub struct TranscribeRequest {
    ...
}

/// Transcription result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transcript {
    ...
}

/// Word with timing information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Word {
    ...
}

/// Speech-to-Text provider trait.
///
/// Implementations provide audio transcription using various services.
#[async_trait]
pub trait SttProvider: Send + Sync {
    /// Provider identifier (e.g., "whisper").
    fn id(&self) -> &'static str;

    /// Human-readable provider name.
    fn name(&self) -> &'static str;

    /// Check if the provider is configured and ready.
    fn is_configured(&self) -> bool;

    /// Transcribe audio to text.
    async fn transcribe(&self, request: TranscribeRequest) -> Result<Transcript>;
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
    ...
}
