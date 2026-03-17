use std::{
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::PathBuf,
};

use {
    crate::{Error, Result},
    fd_lock::RwLock,
    serde::{Deserialize, Serialize},
};

/// A single search hit within a session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    ...
}

/// Append-only JSONL session storage with file locking.
pub struct SessionStore {
    ...
}

#[must_use]
fn slice_on_char_boundaries(content: &str, start: usize, end: usize) -> &str {
    ...
}

impl SessionStore {
    pub fn new(base_dir: PathBuf) -> Self {

    /// Sanitize a session key for use as a filename.
    pub fn key_to_filename(key: &str) -> String {
    ...
}

    fn path_for(&self, key: &str) -> PathBuf {
    ...
}

    /// Directory for session media files (screenshots, audio, etc.).
    fn media_dir_for(&self, key: &str) -> PathBuf {
    ...
}

    /// Save a media file for a session. Returns the relative path from base_dir.
    pub async fn save_media(&self, key: &str, filename: &str, data: &[u8]) -> Result<String> {
    ...
}

    /// Read a media file. Returns raw bytes.
    pub async fn read_media(&self, key: &str, filename: &str) -> Result<Vec<u8>> {
    ...
}

    /// Append a message (JSON value) as a single line to the session file.
    pub async fn append(&self, key: &str, message: &serde_json::Value) -> Result<()> {
    ...
}

    /// Read all messages from a session file.
    pub async fn read(&self, key: &str) -> Result<Vec<serde_json::Value>> {
    ...
}

    /// Read all messages from a session that match a given `run_id`.
    pub async fn read_by_run_id(&self, key: &str, run_id: &str) -> Result<Vec<serde_json::Value>> {
    ...
}

    /// Read the last N messages from a session file.
    pub async fn read_last_n(&self, key: &str, n: usize) -> Result<Vec<serde_json::Value>> {
    ...
}

    /// Delete the session file and its media directory.
    pub async fn clear(&self, key: &str) -> Result<()> {
    ...
}

    /// List all session keys by scanning JSONL files in the base directory.
    pub fn list_keys(&self) -> Vec<String> {
    ...
}

    /// Search all sessions for messages containing `query` (case-insensitive).
    /// Returns up to `max_results` hits, at most one per session.
    pub async fn search(&self, query: &str, max_results: usize) -> Result<Vec<SearchResult>> {
    ...
}

    /// Replace the entire session history with the given messages.
    pub async fn replace_history(&self, key: &str, messages: Vec<serde_json::Value>) -> Result<()> {
    ...
}

    /// Read all messages as typed [`PersistedMessage`] values.
    ///
    /// Lines that fail to deserialize into `PersistedMessage` are skipped
    /// (with a warning), matching the behavior of [`read`].
    pub async fn read_typed(&self, key: &str) -> Result<Vec<crate::message::PersistedMessage>> {
    ...
}

    /// Read the last N messages as typed [`PersistedMessage`] values.
    pub async fn read_last_n_typed(
        &self,
        key: &str,
        n: usize,
    ) -> Result<Vec<crate::message::PersistedMessage>> {
    ...
}

    /// Replace the entire session history with typed messages.
    pub async fn replace_history_typed(
        &self,
        key: &str,
        messages: &[crate::message::PersistedMessage],
    ) -> Result<()> {
    ...
}

    /// Append a typed message to the session file.
    pub async fn append_typed(
        &self,
        key: &str,
        message: &crate::message::PersistedMessage,
    ) -> Result<()> {
    ...
}

    /// Count messages in a session file without parsing them.
    pub async fn count(&self, key: &str) -> Result<u32> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
