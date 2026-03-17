use {
    moltis_channels::{
        config_view::ChannelConfigView,
        gating::{DmPolicy, GroupPolicy},
    },
    serde::{Deserialize, Serialize},
    std::path::PathBuf,
};

/// Configuration for a single WhatsApp account.
///
/// Unlike Telegram, WhatsApp uses Linked Devices (QR code pairing) so no
/// bot token is needed. The Signal Protocol session state is persisted in a
/// per-account store.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct WhatsAppAccountConfig {
    ...
}

impl std::fmt::Debug for WhatsAppAccountConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl ChannelConfigView for WhatsAppAccountConfig {
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

impl Default for WhatsAppAccountConfig {
    fn default() -> Self {
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn deserialize_from_json() {
    ...
}

    #[test]
    fn deserialize_with_access_control() {
    ...
}

    #[test]
    fn serialize_roundtrip() {
    ...
}
}
