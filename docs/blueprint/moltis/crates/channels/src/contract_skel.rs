//! Shared contract tests for the [`ChannelPlugin`] trait.
//!
//! These functions validate that any `ChannelPlugin` implementation satisfies
//! the lifecycle and error-handling semantics required by the registry and
//! gateway. Run against `TestPlugin` in registry tests; real channel plugins
//! only need per-channel descriptor-coherence tests.

use crate::{
    Result,
    plugin::{ChannelPlugin, StreamEvent},
};

/// Start → `has_account` → stop → `!has_account`.
pub async fn lifecycle_start_stop(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

/// Starting the same account twice must not panic.
pub async fn double_start_same_account(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

/// Stopping an unknown account must not panic.
pub async fn stop_unknown_account(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

/// `account_config()` returns `Some` after start for plugins that support it.
pub async fn config_view_after_start(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

/// After `start_account`, `outbound()` must return `Some`.
pub async fn outbound_available_after_start(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

/// After `start_account`, `shared_outbound().send_text()` must return `Ok`.
pub async fn shared_outbound_send_succeeds_after_start(
    plugin: &mut dyn ChannelPlugin,
) -> Result<()> {
    ...
}

/// Sending a stream with `StreamEvent::Done` must complete without error.
pub async fn stream_completes_on_done_signal(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

/// Sending a stream with `StreamEvent::Error` must complete without panicking.
pub async fn stream_completes_on_error_signal(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

/// Sending to an unknown account must return a classifiable (non-retryable) error.
pub async fn outbound_error_classification(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

/// `status().probe()` on an unknown account must return `connected: false`.
pub async fn probe_unknown_account_returns_disconnected(plugin: &dyn ChannelPlugin) -> Result<()> {
    ...
}

/// After `start_account`, `status().probe()` must return `connected: true`.
pub async fn probe_started_account_returns_connected(plugin: &mut dyn ChannelPlugin) -> Result<()> {
    ...
}

// ── Channel webhook verifier contracts ──────────────────────────────────────

use crate::channel_webhook_middleware::{ChannelWebhookRejection, ChannelWebhookVerifier};

/// A verifier must reject an empty body with no signature headers.
pub fn channel_webhook_verifier_rejects_empty_signature(verifier: &dyn ChannelWebhookVerifier) {
    ...
}

/// A verifier must reject a body with an invalid/corrupted signature.
pub fn channel_webhook_verifier_rejects_bad_signature(
    verifier: &dyn ChannelWebhookVerifier,
    headers_with_bad_sig: &http::HeaderMap,
) {
    ...
}

/// A verifier must produce a non-empty `channel_type()`.
pub fn channel_webhook_verifier_has_channel_type(verifier: &dyn ChannelWebhookVerifier) {
    ...
}

/// A verifier's `max_timestamp_age()` must be positive.
pub fn channel_webhook_verifier_has_positive_max_age(verifier: &dyn ChannelWebhookVerifier) {
    ...
}

/// A verifier's `rate_policy()` must have a non-zero rate.
pub fn channel_webhook_verifier_has_valid_rate_policy(verifier: &dyn ChannelWebhookVerifier) {
    ...
}
