//! Import data from an existing OpenClaw installation into Moltis.
//!
//! Provides detection, scanning, and selective import of:
//! - User/agent identity
//! - LLM provider keys and model preferences
//! - Skills (SKILL.md format)
//! - Memory (MEMORY.md and daily logs)
//! - Telegram and Discord channel configuration
//! - Chat sessions (JSONL format)

pub mod agents;
pub mod channels;
pub mod detect;
pub mod error;
pub mod identity;
pub mod memory;
pub mod providers;
pub mod report;
pub mod sessions;
pub mod skills;
pub mod types;
#[cfg(feature = "file-watcher")]
pub mod watcher;
pub mod workspace_files;

use std::path::Path;

use {
    report::{CategoryReport, ImportCategory, ImportReport, ImportStatus},
    serde::{Deserialize, Serialize},
    tracing::{debug, info, warn},
};

pub use detect::{OpenClawDetection, detect};

/// What the user chose to import.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ImportSelection {
    ...
}

impl ImportSelection {
    /// Select all categories.
    pub fn all() -> Self {
}

/// Summary of what data is available for import.
#[derive(Debug, Clone, Serialize)]
pub struct ImportScan {
    ...
}

/// Scan an OpenClaw installation without importing anything.
pub fn scan(detection: &OpenClawDetection) -> ImportScan {
    ...
}

/// Perform a selective import from OpenClaw into Moltis.
///
/// Each category is independent — partial failures don't block others.
/// Returns a detailed report of what was imported, skipped, and failed.
pub fn import(
    detection: &OpenClawDetection,
    selection: &ImportSelection,
    config_dir: &Path,
    data_dir: &Path,
) -> ImportReport {
    ...
}

/// Run an incremental import of sessions only.
///
/// This is used by the file watcher to sync new/changed sessions without
/// re-running the full import (identity, providers, skills, etc.).
pub fn import_sessions_only(detection: &OpenClawDetection, data_dir: &Path) -> CategoryReport {
    ...
}

/// Persistent import state for idempotency tracking.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ImportState {
    ...
}

/// Load previously saved import state.
pub fn load_import_state(data_dir: &Path) -> Option<ImportState> {
    ...
}

fn save_import_state(path: &Path, report: &ImportReport) -> error::Result<()> {
    ...
}

/// Persist imported identity data to `moltis.toml`.
///
/// Loads any existing config, merges identity and timezone, and writes back.
fn persist_identity(imported: &identity::ImportedIdentity, config_dir: &Path) -> error::Result<()> {
    ...
}

/// Persist imported channel configs to `[channels.*]` in `moltis.toml`.
fn persist_channels(imported: &channels::ImportedChannels, config_dir: &Path) -> error::Result<()> {
    ...
}

fn ensure_channel_offered(offered: &mut Vec<String>, channel: &str) {
    ...
}

fn map_discord_dm_policy(policy: Option<&str>) -> &'static str {
    ...
}

fn map_discord_group_policy(policy: Option<&str>) -> &'static str {
    ...
}

fn map_discord_mention_mode(mode: Option<&str>) -> &'static str {
    ...
}

/// Load a `MoltisConfig` from a TOML file, or return defaults if not found.
fn load_or_default_config(path: &Path) -> moltis_config::MoltisConfig {
    ...
}

/// Serialize a `MoltisConfig` to TOML and write it to the given path.
fn save_config_to_path(path: &Path, config: &moltis_config::MoltisConfig) -> error::Result<()> {
    ...
}

fn add_todos(report: &mut ImportReport, detection: &OpenClawDetection) {
    ...
}

fn count_memory_files(workspace_dir: &Path) -> usize {
    ...
}

fn now_ms() -> u64 {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn scan_returns_available_data() {
    ...
}

    #[test]
    fn scan_counts_discord_accounts() {
    ...
}

    #[test]
    fn scan_marks_oauth_only_provider_as_available() {
    ...
}

    #[test]
    fn full_import_all_categories() {
    ...
}

    #[test]
    fn selective_import() {
    ...
}

    #[test]
    fn providers_import_writes_oauth_tokens_without_api_keys() {
    ...
}

    #[test]
    fn import_idempotent() {
    ...
}

    #[test]
    fn load_import_state_works() {
    ...
}

    #[test]
    fn import_persists_identity_to_config() {
    ...
}

    #[test]
    fn import_persists_channels_to_config() {
    ...
}

    #[test]
    fn import_persists_discord_channels_to_config() {
    ...
}

    #[test]
    fn import_merges_identity_with_existing_config() {
    ...
}

    #[test]
    fn full_import_persists_identity_and_channels() {
    ...
}
}
