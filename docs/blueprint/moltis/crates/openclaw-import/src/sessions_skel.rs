//! Import session JSONL files from OpenClaw to Moltis format.
//!
//! OpenClaw sessions live at either:
//! - `~/.openclaw/agents/<id>/sessions/<key>.jsonl` (legacy layout), or
//! - `~/.openclaw/agents/<id>/agent/sessions/<key>.jsonl` (newer layout).
//!
//! Moltis sessions live at `<data_dir>/sessions/<safe-key>.jsonl` with metadata
//! in `metadata.json`.

use std::{
    collections::HashMap,
    io::{BufRead, BufReader, Write},
    path::Path,
};

use {
    serde::{Deserialize, Serialize},
    tracing::{debug, warn},
};

use crate::{
    detect::{OpenClawDetection, resolve_agent_sessions_dir},
    identity::normalize_display_name,
    report::{CategoryReport, ImportCategory, ImportStatus},
    types::{
        OpenClawContent, OpenClawRole, OpenClawSessionIndexEntry, OpenClawSessionOrigin,
        OpenClawSessionRecord, OpenClawTimestamp,
    },
};

/// Minimal session metadata for the Moltis `metadata.json` index.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportedSessionEntry {
    ...
}

/// A converted Moltis message (matches `PersistedMessage` serde format).
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "role", rename_all = "lowercase")]
enum MoltisMessage {
    ...
}

/// Import sessions from all agents in an OpenClaw installation.
///
/// In addition to converting JSONL files, this also generates markdown
/// transcripts in `memory_sessions_dir` (typically `<data>/memory/sessions/`)
/// so that imported conversations are searchable by the Moltis memory system.
///
/// `agent_id_mapping` maps OpenClaw agent IDs to Moltis agent IDs. If empty,
/// agent IDs are used as-is (backward compatible for single-agent installs).
pub fn import_sessions(
    detection: &OpenClawDetection,
    dest_sessions_dir: &Path,
    memory_sessions_dir: &Path,
    agent_id_mapping: &HashMap<String, String>,
) -> CategoryReport {
    ...
}

/// Load the `sessions.json` index and build a reverse map from session-ID
/// (UUID filename stem) to the logical key and origin metadata.
fn load_session_label_map(
    sessions_dir: &Path,
) -> HashMap<String, (String, Option<OpenClawSessionOrigin>)> {
    ...
}

/// Build a human-readable session label from the logical key and origin.
///
/// Key patterns:
/// - `agent:*:main`             → "Main"
/// - `agent:*:telegram:dm:*`    → "Telegram: {cleaned label}"
/// - `agent:*:signal:dm:*`      → "Signal: {cleaned label}"
/// - `agent:*:cron:*`           → "Cron"
/// - Other with origin label    → "OpenClaw: {cleaned label}"
/// - Fallback (no index entry)  → "OpenClaw: {uuid prefix}"
fn build_session_label(logical_key: &str, origin: Option<&OpenClawSessionOrigin>) -> String {
    ...
}

struct ConvertStats {
    ...
}

/// A single entry in a session transcript (for markdown export).
struct TranscriptEntry {
    ...
}

fn convert_session(src: &Path, dest: &Path) -> crate::error::Result<ConvertStats> {
    ...
}

fn convert_message(
    msg: &crate::types::OpenClawMessage,
    timestamp_ms: Option<u64>,
    stats: &mut ConvertStats,
) -> Option<MoltisMessage> {
    ...
}

/// Count lines in a file without parsing content.
fn count_lines(path: &Path) -> u32 {
    ...
}

fn sanitize_session_key(key: &str) -> String {
    ...
}

/// Load existing session metadata from disk.
fn load_session_metadata(path: &Path) -> HashMap<String, ImportedSessionEntry> {
    ...
}

fn merge_session_metadata(
    path: &Path,
    new_entries: &[ImportedSessionEntry],
) -> crate::error::Result<()> {
    ...
}

fn build_preview(transcript: &[TranscriptEntry]) -> Option<String> {
    ...
}

fn normalize_whitespace(text: &str) -> String {
    ...
}

fn truncate_preview(text: &str, max_chars: usize) -> String {
    ...
}

/// Write a markdown transcript of a session for memory search indexing.
///
/// The file is placed in `memory/sessions/` and includes all user/assistant
/// messages so they become searchable by the Moltis memory system.
fn write_transcript(
    dir: &Path,
    dest_key: &str,
    label: &str,
    model: Option<&str>,
    stats: &ConvertStats,
) -> crate::error::Result<()> {
    ...
}

fn now_ms() -> u64 {
    ...
}

fn uuid_v4() -> String {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    fn default_mapping() -> HashMap<String, String> {
    ...
}

    fn setup_session(home: &Path, agent: &str, key: &str, lines: &[&str]) {
    ...
}

    fn setup_session_legacy_layout(home: &Path, agent: &str, key: &str, lines: &[&str]) {
    ...
}

    #[test]
    fn convert_basic_session() {
    ...
}

    #[test]
    fn convert_basic_session_legacy_layout() {
    ...
}

    #[test]
    fn convert_tool_messages() {
    ...
}

    #[test]
    fn import_idempotent() {
    ...
}

    #[test]
    fn no_agents_returns_skipped() {
    ...
}

    #[test]
    fn multi_agent_imports_all() {
    ...
}

    #[test]
    fn session_metadata_written() {
    ...
}

    #[test]
    fn malformed_lines_skipped() {
    ...
}

    #[test]
    fn session_transcript_written() {
    ...
}

    #[test]
    fn model_extracted_from_custom_record() {
    ...
}

    #[test]
    fn incremental_import_detects_growth() {
    ...
}

    #[test]
    fn incremental_import_noop_when_unchanged() {
    ...
}

    #[test]
    fn incremental_import_preserves_id_and_created_at() {
    ...
}

    #[test]
    fn incremental_import_regenerates_transcript() {
    ...
}

    #[test]
    fn incremental_import_upgrades_legacy_metadata() {
    ...
}

    #[test]
    fn preserves_source_timestamps_and_preview() {
    ...
}

    fn write_sessions_json(home: &Path, agent: &str, content: &str) {
    ...
}

    #[test]
    fn session_labels_from_index() {
    ...
}

    #[test]
    fn session_label_telegram_from_index() {
    ...
}

    #[test]
    fn session_label_cron_from_index() {
    ...
}

    #[test]
    fn session_label_fallback_without_index() {
    ...
}

    #[test]
    fn build_session_label_unit_tests() {
    ...
}

    #[test]
    fn load_session_label_map_parses_index() {
    ...
}
}
