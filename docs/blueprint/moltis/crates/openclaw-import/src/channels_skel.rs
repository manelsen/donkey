//! Import channel configuration from OpenClaw (Telegram + Discord).

use std::path::Path;

use {
    serde::{Deserialize, Serialize},
    tracing::debug,
};

use crate::{
    detect::OpenClawDetection,
    report::{CategoryReport, ImportCategory, ImportStatus},
    types::{OpenClawConfig, OpenClawDiscordAccount, OpenClawTelegramAccount},
};

/// Imported Telegram channel configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportedTelegramChannel {
    ...
}

/// Imported Discord channel configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportedDiscordChannel {
    ...
}

/// Import result for channels.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ImportedChannels {
    ...
}

/// Import channel configuration from OpenClaw.
pub fn import_channels(detection: &OpenClawDetection) -> (CategoryReport, ImportedChannels) {
    ...
}

fn extract_telegram_account(
    id: &str,
    account: &OpenClawTelegramAccount,
) -> Option<ImportedTelegramChannel> {
    ...
}

fn extract_discord_account(
    id: &str,
    account: &OpenClawDiscordAccount,
) -> Option<ImportedDiscordChannel> {
    ...
}

/// Parse OpenClaw's `allowFrom` array into Telegram user IDs.
///
/// OpenClaw allows both numbers and strings like `"tg:123456"`.
fn parse_allow_from(values: &[serde_json::Value]) -> Vec<i64> {
    ...
}

/// Parse OpenClaw `allowFrom`/`guildAllowlist` arrays into string IDs.
fn parse_allowlist(values: &[serde_json::Value]) -> Vec<String> {
    ...
}

fn load_config(path: &Path) -> OpenClawConfig {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn import_telegram_accounts() {
    ...
}

    #[test]
    fn import_telegram_flat_config() {
    ...
}

    #[test]
    fn import_discord_accounts() {
    ...
}

    #[test]
    fn import_discord_flat_config() {
    ...
}

    #[test]
    fn import_skips_disabled_accounts() {
    ...
}

    #[test]
    fn import_skips_disabled_discord_accounts() {
    ...
}

    #[test]
    fn parse_allow_from_mixed() {
    ...
}

    #[test]
    fn no_telegram_returns_skipped() {
    ...
}

    #[test]
    fn unsupported_channels_in_warnings() {
    ...
}
}
