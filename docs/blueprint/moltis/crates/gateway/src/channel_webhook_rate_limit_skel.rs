//! Per-(channel, account) token-bucket rate limiter for channel webhooks.
//!
//! Each `(channel_type, account_id)` pair gets its own bucket. Buckets are
//! lazily created on first request and automatically evicted when stale.

use std::time::{Duration, Instant};

use dashmap::DashMap;

use moltis_channels::channel_webhook_middleware::{
    ChannelWebhookRatePolicy, ChannelWebhookRejection,
};

/// Composite key for per-(channel, account) rate limiting.
type BucketKey = String;

fn bucket_key(channel: &str, account_id: &str) -> BucketKey {
    ...
}

/// Token-bucket state for a single (channel, account) pair.
struct Bucket {
    ...
}

/// Concurrent rate limiter using per-account token buckets.
///
/// Thread-safe: uses [`DashMap`] for lock-free concurrent access.
pub struct ChannelWebhookRateLimiter {
    ...
}

impl ChannelWebhookRateLimiter {
    pub fn new() -> Self {

    /// Check the rate limit for a (channel, account) pair.
    ///
    /// Returns `Ok(())` if the request is allowed, or
    /// `Err(ChannelWebhookRejection::RateLimited { .. })` if the bucket is exhausted.
    pub fn check(
        &self,
        channel_type: &str,
        account_id: &str,
        policy: &ChannelWebhookRatePolicy,
    ) -> Result<(), ChannelWebhookRejection> {
    ...
}

    /// Remove stale buckets that haven't been used recently.
    ///
    /// Call this periodically (e.g. every 5 minutes) from a maintenance timer.
    pub fn evict_stale(&self, max_idle: Duration) {
    ...
}

    /// Number of tracked buckets (for diagnostics).
    pub fn bucket_count(&self) -> usize {
    ...
}

    /// Hard eviction when bucket count exceeds limit.
    /// Removes the oldest half of buckets.
    pub fn evict_if_full(&self) {
    ...
}
}

impl Default for ChannelWebhookRateLimiter {
    fn default() -> Self {
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn allows_requests_within_rate() {
    ...
}

    #[test]
    fn rejects_after_burst_exhausted() {
    ...
}

    #[test]
    fn separate_accounts_have_separate_buckets() {
    ...
}

    #[test]
    fn separate_channels_have_separate_buckets() {
    ...
}

    #[test]
    fn evict_stale_removes_old_buckets() {
    ...
}

    #[test]
    fn retry_after_is_positive() {
    ...
}
}
