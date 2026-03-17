//! Voice service implementations for TTS and STT.
//!
//! This module provides concrete implementations of the `TtsService` and
//! `SttService` traits using the moltis-voice crate's providers.

use {
    async_trait::async_trait,
    serde_json::{Value, json},
};

use crate::services::{ServiceError, ServiceResult};

#[cfg(feature = "voice")]
use {
    base64::Engine,
    secrecy::Secret,
    tracing::{debug, info, warn},
};

#[cfg(feature = "voice")]
use moltis_voice::{
    AudioFormat, CoquiTts, DeepgramStt, ElevenLabsStt, ElevenLabsTts, GoogleStt, GoogleTts,
    GroqStt, MistralStt, OpenAiTts, PiperTts, SherpaOnnxStt, SttProvider, SttProviderId,
    SynthesizeRequest, TranscribeRequest, TtsConfig, TtsProvider, TtsProviderId, VoxtralLocalStt,
    WhisperCliStt, WhisperStt, strip_ssml_tags,
};

#[cfg(feature = "voice")]
use crate::services::TtsService;

#[cfg(feature = "voice")]
trait IntoVoiceSttProvider {
    fn into_voice_stt_provider(self) -> moltis_config::VoiceSttProvider;
}

#[cfg(feature = "voice")]
impl IntoVoiceSttProvider for SttProviderId {
    ...
}

/// Resolve an OpenAI API key with fallback: voice-specific config → `OPENAI_API_KEY`
/// env var → LLM provider config (`providers.openai.api_key`).
#[cfg(feature = "voice")]
fn resolve_openai_key(
    voice_key: Option<&Secret<String>>,
    cfg: &moltis_config::MoltisConfig,
) -> Option<Secret<String>> {
    ...
}

// ── TTS Service ─────────────────────────────────────────────────────────────

/// Live TTS service that delegates to voice providers.
/// Reads fresh config on each operation to pick up changes.
#[cfg(feature = "voice")]
pub struct LiveTtsService {
    ...
}

#[cfg(feature = "voice")]
impl std::fmt::Debug for LiveTtsService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

#[cfg(feature = "voice")]
impl LiveTtsService {
    /// Create a new TTS service. Config is read fresh on each operation.
    pub fn new(_config: TtsConfig) -> Self {

    /// Create from environment variables (same as new, config read on demand).
    pub fn from_env() -> Self {
    ...
}

    /// Load fresh TTS config from disk.
    fn load_config() -> TtsConfig {
    ...
}

    /// Create a provider on-demand from fresh config.
    fn create_provider(provider_id: TtsProviderId) -> Option<Box<dyn TtsProvider + Send + Sync>> {
    ...
}

    /// List all providers with their configuration status.
    fn list_providers() -> Vec<(TtsProviderId, bool)> {
    ...
}

    /// Resolve the active provider: explicit config value, or first configured.
    fn resolve_provider(config_provider: &str) -> Option<TtsProviderId> {
    ...
}

    /// Parse provider from JSON params, falling back to config/auto-select.
    fn resolve_from_params(
        params: &Value,
        config_provider: &str,
    ) -> Result<TtsProviderId, ServiceError> {
    ...
}
}

#[cfg(feature = "voice")]
#[async_trait]
impl TtsService for LiveTtsService {
    async fn status(&self) -> ServiceResult {

    async fn providers(&self) -> ServiceResult {
    ...
}

    async fn enable(&self, params: Value) -> ServiceResult {
    ...
}

    async fn disable(&self) -> ServiceResult {
    ...
}

    async fn convert(&self, params: Value) -> ServiceResult {
    ...
}

    async fn set_provider(&self, params: Value) -> ServiceResult {
    ...
}
}

// ── STT Service ─────────────────────────────────────────────────────────────

// `SttService` trait and `NoopSttService` are defined in `moltis-service-traits`
// and re-exported via `crate::services::*`.
pub use crate::services::{NoopSttService, SttService};

/// Live STT service that delegates to voice providers.
/// Reads fresh config on each operation to pick up changes.
#[cfg(feature = "voice")]
pub struct LiveSttService {
    ...
}

#[cfg(feature = "voice")]
impl std::fmt::Debug for LiveSttService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// Configuration for constructing LiveSttService.
#[cfg(feature = "voice")]
pub struct SttServiceConfig {
    ...
}

#[cfg(feature = "voice")]
impl Default for SttServiceConfig {
    fn default() -> Self {
}

#[cfg(feature = "voice")]
impl LiveSttService {
    /// Create a new STT service. Config is read fresh on each operation.
    #[allow(unused_variables)]
    pub fn new(config: SttServiceConfig) -> Self {

    /// Create from environment variables (same as new, config read on demand).
    pub fn from_env() -> Self {
    ...
}

    /// Load fresh STT config from disk and create provider on demand.
    fn create_provider(provider_id: SttProviderId) -> Option<Box<dyn SttProvider + Send + Sync>> {
    ...
}

    /// List all providers with their configuration status (reads fresh config).
    fn list_providers() -> Vec<(SttProviderId, bool)> {
    ...
}

    /// Resolve the active provider: explicit config value, or first configured.
    fn resolve_provider(
        config_provider: Option<moltis_config::VoiceSttProvider>,
    ) -> Option<SttProviderId> {
    ...
}
}

#[cfg(feature = "voice")]
#[async_trait]
impl SttService for LiveSttService {
    async fn status(&self) -> ServiceResult {

    async fn providers(&self) -> ServiceResult {
    ...
}

    async fn transcribe(&self, params: Value) -> ServiceResult {
    ...
}

    async fn transcribe_bytes(
        &self,
        audio: bytes::Bytes,
        format: &str,
        provider: Option<&str>,
        language: Option<&str>,
        prompt: Option<&str>,
    ) -> ServiceResult {
    ...
}

    async fn set_provider(&self, params: Value) -> ServiceResult {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(all(test, feature = "voice"))]
mod tests {
