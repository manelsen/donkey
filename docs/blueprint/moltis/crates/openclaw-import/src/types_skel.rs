//! Concrete types for OpenClaw configuration files.
//!
//! These map the known shape of `~/.openclaw/openclaw.json` (JSON5) and
//! related files into typed Rust structs. Uses `#[serde(default)]`
//! liberally for forward-compatibility with unknown OpenClaw versions.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

// ── openclaw.json root ───────────────────────────────────────────────────────

/// Root of `~/.openclaw/openclaw.json`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawConfig {
    ...
}

// ── agents ───────────────────────────────────────────────────────────────────

/// `agents` section of the OpenClaw config.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawAgentsConfig {
    ...
}

/// `agents.defaults` — global agent defaults.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawAgentDefaults {
    ...
}

/// Model selection: `{primary, fallbacks}`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawModelConfig {
    ...
}

/// A single agent in `agents.list[]`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawAgentEntry {
    ...
}

/// Agent-level model override — can be a string or `{primary, fallbacks}`.
#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum OpenClawAgentModelConfig {
    ...
}

// ── channels ─────────────────────────────────────────────────────────────────

/// `channels` section.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawChannelsConfig {
    ...
}

/// Telegram channel config. OpenClaw supports both flat and `accounts` map forms.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawTelegramConfig {
    ...
}

/// A single Telegram account config.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawTelegramAccount {
    ...
}

/// Discord channel config. OpenClaw supports both flat and `accounts` map forms.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawDiscordConfig {
    ...
}

/// A single Discord account config.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawDiscordAccount {
    ...
}

// ── memory ───────────────────────────────────────────────────────────────────

/// `memory` section.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawMemoryConfig {
    ...
}

// ── ui ───────────────────────────────────────────────────────────────────────

/// `ui` section.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawUiConfig {
    ...
}

/// `ui.assistant` — agent display identity.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawAssistantConfig {
    ...
}

// ── auth-profiles.json ───────────────────────────────────────────────────────

/// Root of `agents/<id>/agent/auth-profiles.json`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct OpenClawAuthProfileStore {
    ...
}

/// A single auth profile credential entry.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum OpenClawAuthProfile {
    ...
}

impl OpenClawAuthProfile {
    /// The provider name for this profile.
    pub fn provider(&self) -> &str {

    /// Extract the API key (only for `api_key` profiles).
    pub fn api_key(&self) -> Option<&str> {
    ...
}
}

// ── Session JSONL records ────────────────────────────────────────────────────

/// A single line in an OpenClaw session JSONL file.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum OpenClawSessionRecord {
    ...
}

/// An OpenClaw chat message within a session record.
#[derive(Debug, Clone, Deserialize)]
pub struct OpenClawMessage {
    ...
}

/// A timestamp in OpenClaw records.
///
/// OpenClaw emits mixed formats:
/// - integer unix milliseconds (`1769582795764`)
/// - floating-point seconds or milliseconds
/// - ISO-8601 strings (`2026-01-28T06:46:35.758Z`)
#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum OpenClawTimestamp {
    ...
}

impl OpenClawTimestamp {
    /// Convert to unix milliseconds.
    #[must_use]
    pub fn to_millis(&self) -> Option<u64> {
}

fn normalize_epoch(value: f64) -> Option<u64> {
    ...
}

fn parse_iso_to_millis(s: &str) -> Option<u64> {
    ...
}

/// OpenClaw message roles.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum OpenClawRole {
    ...
}

/// Message content — either a string or an array of content blocks.
#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum OpenClawContent {
    ...
}

impl OpenClawContent {
    /// Extract as plain text, joining blocks if necessary.
    pub fn as_text(&self) -> String {
}

// ── Session index (sessions.json) ────────────────────────────────────────────

/// A single entry in the `sessions.json` index file.
///
/// The index maps logical session keys (e.g. `agent:main:main`) to metadata
/// including timestamps and origin information.
#[derive(Debug, Deserialize)]
pub struct OpenClawSessionIndexEntry {
    ...
}

/// Origin metadata for a session in `sessions.json`.
#[derive(Debug, Deserialize)]
pub struct OpenClawSessionOrigin {
    ...
}

// ── MCP servers (OpenClaw format) ────────────────────────────────────────────

/// A single MCP server entry in OpenClaw's config.
///
/// OpenClaw typically configures MCP servers in `mcp-servers.json` or within
/// `openclaw.json` plugins — the format matches the Claude Code MCP standard.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct OpenClawMcpServer {
    ...
}

fn default_true() -> bool {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn parse_config_with_comments() {
    ...
}

    #[test]
    fn parse_telegram_flat_config() {
    ...
}

    #[test]
    fn parse_telegram_accounts_config() {
    ...
}

    #[test]
    fn parse_discord_flat_config() {
    ...
}

    #[test]
    fn parse_discord_accounts_config() {
    ...
}

    #[test]
    fn parse_auth_profile_api_key() {
    ...
}

    #[test]
    fn parse_session_record_message() {
    ...
}

    #[test]
    fn parse_session_record_meta() {
    ...
}

    #[test]
    fn parse_session_record_custom() {
    ...
}

    #[test]
    fn parse_agent_model_simple() {
    ...
}

    #[test]
    fn unsupported_channels_detected() {
    ...
}

    #[test]
    fn parse_session_index_entry() {
    ...
}

    #[test]
    fn parse_session_index_entry_minimal() {
    ...
}

    #[test]
    fn content_text_extraction() {
    ...
}
}
