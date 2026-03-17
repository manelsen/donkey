//! sherpa-onnx STT provider implementation.
//!
//! sherpa-onnx provides offline speech recognition using ONNX runtime
//! with support for various ASR models (Whisper, Zipformer, etc.).
//!
//! Installation: https://k2-fsa.github.io/sherpa/onnx/install/index.html
//! Models: https://github.com/k2-fsa/sherpa-onnx/releases

use {
    anyhow::{Context, Result, anyhow},
    async_trait::async_trait,
    std::{path::PathBuf, process::Stdio},
    tokio::process::Command,
};

use super::{SttProvider, TranscribeRequest, Transcript, cli_utils};

/// Binary name for sherpa-onnx offline.
const BINARY_NAME: &str = "sherpa-onnx-offline";

/// sherpa-onnx STT provider for offline speech recognition.
#[derive(Clone, Debug)]
pub struct SherpaOnnxStt {
    ...
}

impl Default for SherpaOnnxStt {
    fn default() -> Self {
}

impl SherpaOnnxStt {
    /// Create a new sherpa-onnx STT provider.
    #[must_use]
    pub fn new() -> Self {

    /// Create with custom options.
    #[must_use]
    pub fn with_options(
        binary_path: Option<String>,
        model_dir: Option<String>,
        language: Option<String>,
    ) -> Self {
    ...
}

    /// Find the sherpa-onnx-offline binary.
    fn find_binary(&self) -> Option<PathBuf> {
    ...
}

    /// Get the model directory, returning an error if not configured.
    fn get_model_dir(&self) -> Result<PathBuf> {
    ...
}

    /// Detect model files in the model directory.
    /// sherpa-onnx models typically have: tokens.txt, encoder.onnx, decoder.onnx
    fn detect_model_files(&self, model_dir: &PathBuf) -> Result<ModelFiles> {
    ...
}
}

/// Model files detected in the model directory.
struct ModelFiles {
    ...
}

/// Find a file in a directory that starts with a given prefix and ends with .onnx
fn find_file_with_prefix(dir: &PathBuf, prefix: &str) -> Option<PathBuf> {
    ...
}

#[async_trait]
impl SttProvider for SherpaOnnxStt {
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

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
