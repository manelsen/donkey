//! Slack Events API webhook handler.
//!
//! Receives HTTP POST requests from Slack's Events API, verifies request
//! signatures using HMAC-SHA256, and dispatches events to the same handlers
//! used by Socket Mode.

use std::sync::Arc;

use {
    hmac::{Hmac, Mac},
    secrecy::ExposeSecret,
    sha2::Sha256,
    slack_morphism::prelude::*,
    tracing::{debug, info},
};

use moltis_channels::{
    ChannelEventSink,
    message_log::MessageLog,
    plugin::{ChannelReplyTarget, ChannelType},
};

use crate::{
    config::SlackAccountConfig,
    state::{AccountState, AccountStateMap},
};

type HmacSha256 = Hmac<Sha256>;

/// Register an Events API account.
///
/// Unlike Socket Mode, this only authenticates the bot token and registers
/// account state. The actual event receiving is done by the HTTP webhook
/// handler in the gateway server.
pub async fn register_events_api_account(
    account_id: &str,
    config: SlackAccountConfig,
    accounts: AccountStateMap,
    message_log: Option<Arc<dyn MessageLog>>,
    event_sink: Option<Arc<dyn ChannelEventSink>>,
) -> moltis_channels::Result<()> {
    ...
}

/// Verify the Slack request signature (HMAC-SHA256).
///
/// Slack sends:
/// - `X-Slack-Signature`: `v0=<hex-hmac>`
/// - `X-Slack-Request-Timestamp`: epoch seconds
///
/// The HMAC base string is `v0:{timestamp}:{body}`.
pub fn verify_signature(
    signing_secret: &str,
    timestamp: &str,
    body: &[u8],
    signature: &str,
) -> bool {
    ...
}

/// Simple hex decoding (avoids adding another dependency).
fn hex_decode(hex: &str) -> Result<Vec<u8>, ()> {
    ...
}

/// Handle an Events API webhook request.
///
/// Returns `Ok(Some(challenge))` for URL verification requests,
/// `Ok(None)` for normal event dispatches.
pub async fn handle_webhook(
    account_id: &str,
    body: &[u8],
    timestamp: &str,
    signature: &str,
    accounts: &AccountStateMap,
) -> moltis_channels::Result<Option<String>> {
    ...
}

/// Handle an already-verified Events API webhook request.
///
/// The caller (channel webhook middleware) has already verified the signature,
/// checked timestamp staleness, and performed idempotency dedup.
///
/// Returns `Ok(Some(challenge))` for URL verification, `Ok(None)` for events.
pub async fn handle_verified_webhook(
    account_id: &str,
    body: &[u8],
    accounts: &AccountStateMap,
) -> moltis_channels::Result<Option<String>> {
    ...
}

/// Handle an already-verified interaction webhook request.
///
/// The caller (channel webhook middleware) has already verified the signature.
pub async fn handle_verified_interaction_webhook(
    account_id: &str,
    body: &[u8],
    accounts: &AccountStateMap,
) -> moltis_channels::Result<()> {
    ...
}

/// Dispatch an event_callback payload to the appropriate handler.
async fn dispatch_event_callback(
    account_id: &str,
    payload: &serde_json::Value,
    accounts: &AccountStateMap,
) {
    ...
}

/// Handle an interaction payload from the Events API.
///
/// Slack sends interaction payloads as `application/x-www-form-urlencoded`
/// with a `payload` field containing JSON.
pub async fn handle_interaction_webhook(
    account_id: &str,
    body: &[u8],
    timestamp: &str,
    signature: &str,
    accounts: &AccountStateMap,
) -> moltis_channels::Result<()> {
    ...
}

/// Extract the `payload` field from a `application/x-www-form-urlencoded` body.
fn extract_form_payload(body: &str) -> Option<String> {
    ...
}

/// Simple percent-decoding for URL-encoded strings.
fn url_decode(input: &str) -> Option<String> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn verify_rejects_bad_signature() {
    ...
}

    #[test]
    fn verify_rejects_missing_prefix() {
    ...
}

    #[test]
    fn hex_decode_valid() {
    ...
}

    #[test]
    fn hex_decode_odd_length() {
    ...
}

    #[test]
    fn url_decode_basic() {
    ...
}

    #[test]
    fn url_decode_json_payload() {
    ...
}

    #[test]
    fn extract_form_payload_finds_payload() {
    ...
}

    #[test]
    fn extract_form_payload_missing() {
    ...
}
}
