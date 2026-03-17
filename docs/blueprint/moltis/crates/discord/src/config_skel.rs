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

/// Discord bot activity type for presence display.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActivityType {
    ...
}

/// Bot online status.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OnlineStatus {
    ...
}

/// Configuration for a single Discord bot account.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct DiscordAccountConfig {
    ...
}

impl std::fmt::Debug for DiscordAccountConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl ChannelConfigView for DiscordAccountConfig {
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

impl Default for DiscordAccountConfig {
    fn default() -> Self {
}

fn serialize_secret<S: serde::Serializer>(
    secret: &Secret<String>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(secret.expose_secret())
}

#[cfg(test)]
mod tests {

    #[test]
    fn config_defaults() {
    ...
}

    #[test]
    fn config_with_reply_and_ack() {
    ...
}

    #[test]
    fn config_with_presence() {
    ...
}

    #[test]
    fn config_with_otp() {
    ...
}

    #[test]
    fn activity_type_serde_round_trip() {
    ...
}

    #[test]
    fn online_status_serde_round_trip() {
    ...
}

    #[test]
    fn config_full_round_trip_with_all_fields() {
    ...
}

    #[test]
    fn presence_fields_serialized_when_set() {
    ...
}

    #[test]
    fn presence_fields_omitted_when_none() {
    ...
}

    #[test]
    fn activity_type_default_is_custom() {
    ...
}

    #[test]
    fn online_status_default_is_online() {
    ...
}

    #[test]
    fn debug_redacts_token() {
    ...
}

    #[test]
    fn debug_includes_presence_fields() {
    ...
}

    #[test]
    fn debug_includes_otp_fields() {
    ...
}

    #[test]
    fn invalid_activity_type_rejected() {
    ...
}

    #[test]
    fn config_defaults_include_empty_overrides() {
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
    fn invalid_online_status_rejected() {
    ...
}
}
