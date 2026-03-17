//! Microsoft Teams webhook verifier implementing [`ChannelWebhookVerifier`].
//!
//! Uses a shared-secret query parameter (injected as the
//! `x-moltis-webhook-secret` header by the gateway route handler) with
//! constant-time comparison.

use {
    bytes::Bytes,
    http::HeaderMap,
    moltis_channels::{
        channel_webhook_middleware::{
            ChannelWebhookRejection, ChannelWebhookVerifier, VerifiedChannelWebhook,
        },
        plugin::ChannelType,
    },
    secrecy::{ExposeSecret, Secret},
    subtle::ConstantTimeEq,
};

/// Teams webhook verifier using shared-secret comparison.
///
/// The gateway route handler extracts `?secret=<value>` from the query string
/// and places it in the `x-moltis-webhook-secret` header before calling this
/// verifier.
pub struct TeamsChannelWebhookVerifier {
    ...
}

impl TeamsChannelWebhookVerifier {
    pub fn new(webhook_secret: Option<Secret<String>>, require_secret: bool) -> Self {
}

impl ChannelWebhookVerifier for TeamsChannelWebhookVerifier {
    fn verify(
        &self,
        headers: &HeaderMap,
        body: &[u8],
    ) -> Result<VerifiedChannelWebhook, ChannelWebhookRejection> {

    fn channel_type(&self) -> ChannelType {
    ...
}
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn valid_secret_passes() {
    ...
}

    #[test]
    fn wrong_secret_rejects() {
    ...
}

    #[test]
    fn missing_secret_header_rejects() {
    ...
}

    #[test]
    fn require_secret_but_not_configured_rejects() {
    ...
}

    #[test]
    fn no_secret_configured_and_not_required_passes() {
    ...
}

    #[test]
    fn empty_secret_configured_and_not_required_passes() {
    ...
}

    #[test]
    fn no_id_field_yields_none_idempotency_key() {
    ...
}

    #[test]
    fn channel_type_is_msteams() {
    ...
}

    // ── Contract tests ──────────────────────────────────────────────────────

    #[test]
    fn contract_rejects_empty_signature() {
    ...
}

    #[test]
    fn contract_rejects_bad_signature() {
    ...
}

    #[test]
    fn contract_has_channel_type() {
    ...
}

    #[test]
    fn contract_has_positive_max_age() {
    ...
}

    #[test]
    fn contract_has_valid_rate_policy() {
    ...
}
}
