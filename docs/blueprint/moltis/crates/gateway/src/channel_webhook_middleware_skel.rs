//! Channel webhook middleware pipeline.
//!
//! The [`channel_webhook_gate`] function is the single entry point for all
//! webhook-based channel routes. It runs:
//!
//! 1. Signature verification (via the channel's [`ChannelWebhookVerifier`])
//! 2. Timestamp staleness rejection
//! 3. Per-(channel, account) rate limiting
//! 4. Idempotency deduplication

use axum::{
    http::StatusCode,
    response::{IntoResponse as _, Response},
};

use moltis_channels::channel_webhook_middleware::{
    ChannelWebhookDedupeResult, ChannelWebhookRejection, ChannelWebhookVerifier, TimestampGuard,
    VerifiedChannelWebhook,
};

use crate::{
    channel_webhook_dedup::ChannelWebhookDedupeStore,
    channel_webhook_rate_limit::ChannelWebhookRateLimiter,
};

/// Run the full channel webhook verification pipeline.
///
/// Steps:
/// 1. Verify the cryptographic signature via the channel's verifier.
/// 2. Check the timestamp is within the acceptable staleness window.
/// 3. Apply per-(channel, account) rate limiting.
/// 4. Deduplicate by provider message ID (if present).
///
/// On success returns the verified envelope and the dedup result.
/// On failure returns a rejection that maps to an HTTP response.
pub fn channel_webhook_gate(
    verifier: &dyn ChannelWebhookVerifier,
    dedup_store: &std::sync::RwLock<ChannelWebhookDedupeStore>,
    rate_limiter: &ChannelWebhookRateLimiter,
    account_id: &str,
    headers: &axum::http::HeaderMap,
    body: &[u8],
) -> Result<(VerifiedChannelWebhook, ChannelWebhookDedupeResult), ChannelWebhookRejection> {
    ...
}

/// Convert a [`ChannelWebhookRejection`] into an axum HTTP [`Response`].
pub fn rejection_into_response(rejection: ChannelWebhookRejection) -> Response {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
