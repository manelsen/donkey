use {
    moltis_channels::{
        config_view::ChannelConfigView,
        gating::{DmPolicy, GroupPolicy, MentionMode},
    },
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
};

/// Configuration for a single Microsoft Teams bot account.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct MsTeamsAccountConfig {
    ...
}

impl std::fmt::Debug for MsTeamsAccountConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

fn serialize_secret<S: serde::Serializer>(
    secret: &Secret<String>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(secret.expose_secret())
}

fn serialize_option_secret<S: serde::Serializer>(
    secret: &Option<Secret<String>>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    match secret {
        Some(s) => serializer.serialize_some(s.expose_secret()),
        None => serializer.serialize_none(),
    }
}

impl ChannelConfigView for MsTeamsAccountConfig {
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
}

impl Default for MsTeamsAccountConfig {
    fn default() -> Self {
}
