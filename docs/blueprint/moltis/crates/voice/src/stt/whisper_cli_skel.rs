//! whisper-cli (whisper.cpp) STT provider implementation.
//!
//! whisper.cpp is a port of OpenAI's Whisper model to C/C++, offering
//! fast local inference on CPU or GPU. This provider wraps the CLI tool.
//!
//! Installation:
//! - macOS: `brew install whisper-cpp`
//! - From source: https://github.com/ggerganov/whisper.cpp
//!
//! Models can be downloaded from:
//! https://huggingface.co/ggerganov/whisper.cpp

use {
    anyhow::{Context, Result, anyhow},
    async_trait::async_trait,
    serde::Deserialize,
    std::process::Stdio,
    tokio::process::Command,
};

use super::{SttProvider, TranscribeRequest, Transcript, Word, cli_utils};

/// Binary name for whisper.cpp CLI.
const BINARY_NAME: &str = "whisper-cli";

/// Alternative binary name (some installations use this).
const ALT_BINARY_NAME: &str = "whisper";

/// whisper-cli (whisper.cpp) STT provider.
#[derive(Clone, Debug)]
pub struct WhisperCliStt {
    ...
}

impl Default for WhisperCliStt {
    fn default() -> Self {
}

impl WhisperCliStt {
    /// Create a new whisper-cli STT provider.
    #[must_use]
    pub fn new() -> Self {

    /// Create with custom options.
    #[must_use]
    pub fn with_options(
        binary_path: Option<String>,
        model_path: Option<String>,
        language: Option<String>,
    ) -> Self {
    ...
}

    /// Find the whisper-cli binary.
    fn find_binary(&self) -> Option<std::path::PathBuf> {
    ...
}

    /// Get the model path, returning an error if not configured.
    fn get_model_path(&self) -> Result<std::path::PathBuf> {
    ...
}
}

#[async_trait]
impl SttProvider for WhisperCliStt {
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

// ── CLI Output Types ──────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct WhisperCliResponse {
    ...
}

#[derive(Debug, Default, Deserialize)]
struct WhisperCliResult {
    ...
}

#[derive(Debug, Deserialize)]
struct WhisperCliSegment {
    ...
}

#[derive(Debug, Deserialize)]
struct WhisperCliTimestamp {
    ...
}

#[derive(Debug, Deserialize)]
struct WhisperCliOffsets {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
