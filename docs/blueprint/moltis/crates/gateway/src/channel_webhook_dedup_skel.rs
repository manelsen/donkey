//! Channel webhook idempotency deduplication store.
//!
//! Provides TTL-based deduplication for channel webhook requests keyed by
//! provider-specific message IDs (e.g. Slack `event_id`, Teams `activity.id`).
//!
//! Extracted from the former `DedupeCache` in `state.rs`.

use std::{collections::HashMap, time::Instant};

struct DedupeEntry {
    ...
}

/// TTL-based idempotency store for channel webhook deduplication.
///
/// Tracks provider-specific message IDs to detect duplicate deliveries.
/// Entries expire after `ttl` and the store caps at `max_entries`.
pub struct ChannelWebhookDedupeStore {
    ...
}

impl Default for ChannelWebhookDedupeStore {
    fn default() -> Self {
}

impl ChannelWebhookDedupeStore {
    pub fn new() -> Self {

    /// Returns `true` if the key is a duplicate (already seen within TTL).
    /// If new, inserts the key and returns `false`.
    pub fn check_and_insert(&mut self, key: &str) -> bool {
    ...
}

    fn evict_expired(&mut self) {
    ...
}
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn duplicate_key_returns_true() {
    ...
}

    #[test]
    fn different_keys_are_independent() {
    ...
}

    #[test]
    fn evicts_oldest_at_capacity() {
    ...
}
}
