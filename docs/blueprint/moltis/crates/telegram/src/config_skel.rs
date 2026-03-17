use std::collections::HashMap;

use {
    moltis_channels::{
        config_view::ChannelConfigView,
        gating::{DmPolicy, GroupPolicy, MentionMode},
    },
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
};

/// Per-channel model/provider override.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChannelOverride {
    ...
}

/// Per-user model/provider override.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserOverride {
    ...
}

/// How streaming responses are delivered.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StreamMode {
    ...
}

/// Configuration for a single Telegram bot account.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct TelegramAccountConfig {
    ...
}

impl std::fmt::Debug for TelegramAccountConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

fn serialize_secret<S: serde::Serializer>(
    secret: &Secret<String>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(secret.expose_secret())
}

impl ChannelConfigView for TelegramAccountConfig {
    fn allowlist(&self) -> &[String] {

    fn group_allowlist(&self) -> &[String] {
    ...
}

    fn dm_policy(&self) -> DmPolicy {
    ...
}

    fn group_policy(&self) -> GroupPolicy {
    ...
}

    fn model(&self) -> Option<&str> {
    ...
}

    fn model_provider(&self) -> Option<&str> {
    ...
}

    fn channel_model(&self, channel_id: &str) -> Option<&str> {
    ...
}

    fn channel_model_provider(&self, channel_id: &str) -> Option<&str> {
    ...
}

    fn user_model(&self, user_id: &str) -> Option<&str> {
    ...
}

    fn user_model_provider(&self, user_id: &str) -> Option<&str> {
    ...
}
}

impl Default for TelegramAccountConfig {
    fn default() -> Self {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn deserialize_from_json() {
    ...
}

    #[test]
    fn default_config_has_empty_overrides() {
    ...
}

    #[test]
    fn resolve_model_user_overrides_channel() {
    ...
}

    #[test]
    fn overrides_round_trip() {
    ...
}

    #[test]
    fn serialize_roundtrip() {
    ...
}
}
