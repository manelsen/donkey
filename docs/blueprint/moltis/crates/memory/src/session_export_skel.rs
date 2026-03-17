//! Session export: save sanitized session transcripts to memory for cross-run recall.
//!
//! This module provides functionality to export chat sessions as markdown files
//! that can be indexed by the memory system, enabling recall of past conversations.

use std::path::{Path, PathBuf};

use {
    chrono::{DateTime, Utc},
    tokio::fs,
    tracing::{debug, info, warn},
};

/// Configuration for session export.
#[derive(Debug, Clone)]
pub struct SessionExportConfig {
    ...
}

impl Default for SessionExportConfig {
    fn default() -> Self {
}

/// A turn in a session transcript.
#[derive(Debug, Clone)]
pub struct SessionTurn {
    ...
}

/// A session transcript for export.
#[derive(Debug, Clone)]
pub struct SessionTranscript {
    ...
}

impl SessionTranscript {
    /// Create a new session transcript.
    pub fn new(session_id: impl Into<String>) -> Self {

    /// Add a turn to the transcript.
    pub fn add_turn(&mut self, role: impl Into<String>, content: impl Into<String>) {
    ...
}

    /// Convert to markdown format for storage.
    pub fn to_markdown(&self) -> String {
    ...
}
}

/// Sanitize content for export.
/// Removes potentially sensitive information like:
/// - Tool call results with raw data
/// - System messages
/// - Internal metadata
fn sanitize_content(content: &str) -> String {
    ...
}