//! Shared utilities for CLI-based STT providers.
//!
//! Provides common functionality for local STT tools like whisper.cpp
//! and sherpa-onnx that run as command-line processes.

use {
    anyhow::{Context, Result},
    std::path::PathBuf,
    tempfile::NamedTempFile,
};

use crate::tts::AudioFormat;

/// Find a binary in PATH or at a specific path.
///
/// If `config_path` is Some, it's checked first. If None or not found,
/// searches the system PATH.
pub fn find_binary(name: &str, config_path: Option<&str>) -> Option<PathBuf> {
    ...
}

/// Expand `~` to the user's home directory.
pub fn expand_tilde(path: &str) -> PathBuf {
    ...
}

/// Write audio data to a temporary file for CLI processing.
///
/// Returns the temp file handle (keeps file alive) and its path.
pub fn write_temp_audio(audio: &[u8], format: AudioFormat) -> Result<(NamedTempFile, PathBuf)> {
    ...
}

/// Check if a model file or directory exists.
#[allow(dead_code)]
pub fn model_exists(path_str: Option<&str>) -> bool {
    ...
}

/// Verify a binary is executable.
#[allow(dead_code)]
pub fn is_binary_configured(binary_name: &str, config_path: Option<&str>) -> bool {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_find_binary_in_path() {
    ...
}

    #[test]
    fn test_write_temp_audio() {
    ...
}

    #[test]
    fn test_model_exists() {
    ...
}
}
