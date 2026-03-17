use std::time::Duration;

use moltis_config::VoiceSttProvider;

/// Check if Python 3.10+ is available.
pub(super) async fn check_python_version() -> serde_json::Value {
    ...
}

/// Check CUDA availability via nvidia-smi.
pub(super) async fn check_cuda_availability() -> serde_json::Value {
    ...
}

/// Check if the system meets Voxtral Local requirements.
pub(super) fn check_voxtral_compatibility(
    os: &str,
    arch: &str,
    python: &serde_json::Value,
    cuda: &serde_json::Value,
) -> (bool, Vec<String>) {
    ...
}

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub(super) enum VoiceProviderId {
    ...
}

/// Static UI metadata for a voice provider (description, key hints, URLs).
struct VoiceProviderMeta {
    ...
}

impl VoiceProviderId {
    fn meta(self) -> VoiceProviderMeta {

    fn parse_tts_list_id(id: &str) -> Option<Self> {
    ...
}

    fn parse_stt_list_id(id: &str) -> Option<Self> {
    ...
}
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct VoiceProviderInfo {
    ...
}

#[derive(Debug, Clone, serde::Serialize)]
pub(super) struct VoiceProvidersResponse {
    ...
}

/// Detect all available voice providers with their availability status.
pub(super) async fn detect_voice_providers(
    config: &moltis_config::MoltisConfig,
) -> serde_json::Value {
    ...
}

fn filter_listed_voice_providers(
    providers: Vec<VoiceProviderInfo>,
    listed_provider_ids: &[String],
    parse_provider_id: fn(&str) -> Option<VoiceProviderId>,
) -> Vec<VoiceProviderInfo> {
    ...
}

fn enrich_voice_provider(
    mut provider: VoiceProviderInfo,
    config: &moltis_config::MoltisConfig,
) -> VoiceProviderInfo {
    ...
}

fn format_voice_summary(primary: Option<String>, secondary: Option<String>) -> Option<String> {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct ElevenLabsVoiceListResponse {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct ElevenLabsVoice {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct ElevenLabsModel {
    ...
}

pub(super) async fn fetch_elevenlabs_catalog(
    config: &moltis_config::MoltisConfig,
) -> serde_json::Value {
    ...
}

fn build_provider_info(
    id: VoiceProviderId,
    name: &str,
    provider_type: &str,
    category: &str,
    available: bool,
    enabled: bool,
    key_source: Option<&str>,
    binary_path: Option<String>,
    status_message: Option<&str>,
) -> VoiceProviderInfo {
    ...
}

fn key_source(in_config: bool, in_env: bool, in_llm_provider: bool) -> Option<&'static str> {
    ...
}

pub(super) fn apply_voice_provider_settings(
    cfg: &mut moltis_config::MoltisConfig,
    provider: &str,
    params: &serde_json::Value,
) {
    ...
}

async fn check_binary_available(name: &str) -> Option<String> {
    ...
}

/// Check if Coqui TTS server is running.
async fn check_coqui_server(endpoint: &str) -> bool {
    ...
}

/// Check if vLLM server is running (for Voxtral local).
async fn check_vllm_server(endpoint: &str) -> bool {
    ...
}

/// Toggle a voice provider on/off by updating the config file.
pub(super) fn toggle_voice_provider(
    provider: &str,
    enabled: bool,
    provider_type: &str,
) -> Result<(), anyhow::Error> {
    ...
}

#[cfg(test)]
mod tests {
