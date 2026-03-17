//! Channel webhook middleware: shared types for webhook security verification.
//!
//! Channel adapters that receive HTTP webhooks implement [`ChannelWebhookVerifier`]
//! to provide their signature algorithm. The gateway runs the shared pipeline
//! (`channel_webhook_gate`) which handles staleness, idempotency, and rate limiting.
//!
//! This is infrastructure middleware, NOT a user-facing webhook channel.

use std::time::Duration;

use {bytes::Bytes, http::HeaderMap};

use crate::plugin::ChannelType;

// ── Verifier trait ──────────────────────────────────────────────────────────

/// Per-channel webhook signature verification.
///
/// Each webhook channel (Slack, Teams, etc.) implements this trait to provide
/// its platform-specific signature algorithm. The gateway's middleware pipeline
/// calls [`verify`](Self::verify) on every inbound webhook request.
pub trait ChannelWebhookVerifier: Send + Sync {
    /// Verify the cryptographic signature of a webhook request.
    ///
    /// Implementors should:
    /// - Extract the signature from `headers`
    /// - Compute the expected signature from `body` using the channel's secret
    /// - Use constant-time comparison
    ///
    /// Returns a [`VerifiedChannelWebhook`] on success.
    fn verify(
        &self,
        headers: &HeaderMap,
        body: &[u8],
    ) -> Result<VerifiedChannelWebhook, ChannelWebhookRejection>;

    /// Maximum acceptable age of the request timestamp (default: 5 minutes).
    ///
    /// Requests older than this are rejected as stale. Slack recommends 5 minutes.
    fn max_timestamp_age(&self) -> Duration {
    ...
}

    /// Per-account rate policy for this channel (default: 60 req/min, burst 10).
    ///
    /// Channels with higher expected webhook volume can override this.
    fn rate_policy(&self) -> ChannelWebhookRatePolicy {
    ...
}

    /// The channel type this verifier handles. Used for metrics labels.
    fn channel_type(&self) -> ChannelType;
}

// ── Verified envelope ───────────────────────────────────────────────────────

/// Output of a successfully verified webhook request.
#[derive(Debug, Clone)]
pub struct VerifiedChannelWebhook {
    ...
}

// ── Dedup result ────────────────────────────────────────────────────────────

/// Result of an idempotency check.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelWebhookDedupeResult {
    ...
}

// ── Rejection ───────────────────────────────────────────────────────────────

/// Rejection reasons from the channel webhook middleware pipeline.
#[derive(Debug, Clone)]
pub enum ChannelWebhookRejection {
    ...
}

impl ChannelWebhookRejection {
    /// Label value for the `rejection_reason` metric label.
    pub fn reason_label(&self) -> &'static str {
}

impl std::fmt::Display for ChannelWebhookRejection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

// ── Timestamp guard ─────────────────────────────────────────────────────────

/// Checks whether a request timestamp is within the acceptable staleness window.
pub struct TimestampGuard;

impl TimestampGuard {
    /// Returns `Ok(())` if the timestamp is within `max_age` of now.
    ///
    /// If `timestamp_epoch` is `None`, the check passes (channel doesn't
    /// provide timestamps). Rejects both stale and future timestamps.
    pub fn check(
        timestamp_epoch: Option<i64>,
        max_age: Duration,
    ) -> Result<(), ChannelWebhookRejection> {
}

// ── Rate policy ─────────────────────────────────────────────────────────────

/// Rate policy for per-(channel, account) webhook rate limiting.
#[derive(Debug, Clone, Copy)]
pub struct ChannelWebhookRatePolicy {
    ...
}

impl Default for ChannelWebhookRatePolicy {
    fn default() -> Self {
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn timestamp_guard_accepts_recent() {
    ...
}

    #[test]
    fn timestamp_guard_rejects_stale() {
    ...
}

    #[test]
    fn timestamp_guard_passes_when_none() {
    ...
}

    #[test]
    fn timestamp_guard_boundary_exactly_at_max() {
    ...
}

    #[test]
    fn timestamp_guard_boundary_one_past() {
    ...
}

    #[test]
    fn timestamp_guard_rejects_future_timestamps() {
    ...
}

    #[test]
    fn default_rate_policy_is_sensible() {
    ...
}

    #[test]
    fn rejection_reason_labels_are_stable() {
    ...
}
}
