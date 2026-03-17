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

/// How this Slack account connects to Slack.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionMode {
    ...
}

/// Stream mode for Slack responses.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StreamMode {
    ...
}

/// Configuration for a single Slack bot account.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct SlackAccountConfig {
    ...
}

impl std::fmt::Debug for SlackAccountConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl Default for SlackAccountConfig {
    fn default() -> Self {
}

impl ChannelConfigView for SlackAccountConfig {
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

fn serialize_secret<S: serde::Serializer>(
    secret: &Secret<String>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(secret.expose_secret())
}

fn serialize_optional_secret<S: serde::Serializer>(
    secret: &Option<Secret<String>>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    match secret {
        Some(s) => serializer.serialize_str(s.expose_secret()),
        None => serializer.serialize_none(),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn config_view_defaults() {
    ...
}

    #[test]
    fn config_with_tokens_round_trip() {
    ...
}

    #[test]
    fn stream_mode_off() {
    ...
}

    #[test]
    fn stream_mode_native() {
    ...
}

    #[test]
    fn debug_redacts_tokens() {
    ...
}

    #[test]
    fn defaults_are_sensible() {
    ...
}

    #[test]
    fn connection_mode_events_api_round_trip() {
    ...
}

    #[test]
    fn debug_redacts_signing_secret() {
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
}
