//! Slack webhook verifier implementing [`ChannelWebhookVerifier`].
//!
//! Uses HMAC-SHA256 with the app's signing secret, following the
//! [Slack verification protocol](https://api.slack.com/authentication/verifying-requests-from-slack).

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
};

use crate::webhook::verify_signature;

/// Slack Events API / Interactions webhook verifier.
///
/// Wraps the existing HMAC-SHA256 [`verify_signature`] function behind the
/// shared [`ChannelWebhookVerifier`] trait.
pub struct SlackChannelWebhookVerifier {
    ...
}

impl SlackChannelWebhookVerifier {
    pub fn new(signing_secret: Secret<String>) -> Self {
}

impl ChannelWebhookVerifier for SlackChannelWebhookVerifier {
    fn verify(
        &self,
        headers: &HeaderMap,
        body: &[u8],
    ) -> Result<VerifiedChannelWebhook, ChannelWebhookRejection> {

    fn rate_policy(&self) -> moltis_channels::ChannelWebhookRatePolicy {
    ...
}

    fn channel_type(&self) -> ChannelType {
    ...
}
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    const TEST_SECRET: &str = "test_signing_secret_123";

    /// Build valid Slack signature headers for a given body and timestamp.
    fn make_signed_headers(secret: &str, timestamp: &str, body: &[u8]) -> HeaderMap {
    ...
}

    #[test]
    fn valid_signature_passes() {
    ...
}

    #[test]
    fn bad_signature_rejects() {
    ...
}

    #[test]
    fn missing_timestamp_header_rejects() {
    ...
}

    #[test]
    fn missing_signature_header_rejects() {
    ...
}

    #[test]
    fn no_event_id_yields_none_idempotency_key() {
    ...
}

    #[test]
    fn channel_type_is_slack() {
    ...
}

    #[test]
    fn rate_policy_is_30_per_minute() {
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
