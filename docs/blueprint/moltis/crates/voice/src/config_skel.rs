//! Voice configuration types.

use {
    secrecy::Secret,
    serde::{Deserialize, Serialize},
    std::fmt,
};

// ── Provider ID Enums ───────────────────────────────────────────────────────

/// Text-to-Speech provider identifiers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum TtsProviderId {
    ...
}

impl fmt::Display for TtsProviderId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
}

impl TtsProviderId {
    /// Parse from string (for API compatibility).
    pub fn parse(s: &str) -> Option<Self> {

    /// Get human-readable name.
    pub fn name(&self) -> &'static str {
    ...
}

    /// All TTS provider IDs.
    pub fn all() -> &'static [Self] {
    ...
}
}

/// Speech-to-Text provider identifiers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum SttProviderId {
    ...
}

impl fmt::Display for SttProviderId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
}

impl SttProviderId {
    /// Parse from string (for API compatibility).
    pub fn parse(s: &str) -> Option<Self> {

    /// Get human-readable name.
    pub fn name(&self) -> &'static str {
    ...
}

    /// All STT provider IDs.
    pub fn all() -> &'static [Self] {
    ...
}
}

// ── Configuration Structs ───────────────────────────────────────────────────

/// Top-level voice configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct VoiceConfig {
    ...
}

/// Text-to-Speech configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct TtsConfig {
    ...
}

impl Default for TtsConfig {
    fn default() -> Self {
}

/// Auto-speak mode for TTS.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TtsAutoMode {
    ...
}

/// ElevenLabs provider configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ElevenLabsConfig {
    ...
}

/// OpenAI TTS provider configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct OpenAiTtsConfig {
    ...
}

/// Google Cloud TTS provider configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct GoogleTtsConfig {
    ...
}

/// Piper TTS (local) configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct PiperTtsConfig {
    ...
}

/// Coqui TTS (local) configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct CoquiTtsConfig {
    ...
}

impl Default for CoquiTtsConfig {
    fn default() -> Self {
}

/// ElevenLabs Scribe STT configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ElevenLabsSttConfig {
    ...
}

/// Speech-to-Text configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct SttConfig {
    ...
}

impl Default for SttConfig {
    fn default() -> Self {
}

/// OpenAI Whisper configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct WhisperConfig {
    ...
}

/// Groq STT configuration (Whisper-compatible API).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct GroqSttConfig {
    ...
}

/// Deepgram STT configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct DeepgramConfig {
    ...
}

/// Google Cloud Speech-to-Text configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct GoogleSttConfig {
    ...
}

/// Mistral AI (Voxtral Transcribe) configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct MistralSttConfig {
    ...
}

/// whisper-cli (whisper.cpp) configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct WhisperCliConfig {
    ...
}

/// sherpa-onnx offline configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct SherpaOnnxConfig {
    ...
}

/// Voxtral local (vLLM) configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct VoxtralLocalConfig {
    ...
}

impl Default for VoxtralLocalConfig {
    fn default() -> Self {
}

// ── Secret serialization helpers ───────────────────────────────────────────

fn serialize_option_secret<S>(
    value: &Option<Secret<String>>,
    serializer: S,
) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    use secrecy::ExposeSecret;
    match value {
        Some(secret) => serializer.serialize_some(secret.expose_secret()),
        None => serializer.serialize_none(),
    }
}

fn deserialize_option_secret<'de, D>(deserializer: D) -> Result<Option<Secret<String>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let opt: Option<String> = Option::deserialize(deserializer)?;
    Ok(opt.map(Secret::new))
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_default_tts_config() {
    ...
}

    #[test]
    fn test_default_stt_config() {
    ...
}

    #[test]
    fn test_tts_auto_mode_serde() {
    ...
}

    #[test]
    fn test_voice_config_roundtrip() {
    ...
}
}
