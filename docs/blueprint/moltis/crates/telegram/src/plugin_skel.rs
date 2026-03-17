use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
    time::Instant,
};

use {
    async_trait::async_trait,
    secrecy::ExposeSecret,
    teloxide::prelude::Requester,
    tracing::{info, warn},
};

use moltis_channels::{
    ChannelConfigView, ChannelEventSink, Error as ChannelError, Result as ChannelResult,
    message_log::MessageLog,
    otp::OtpChallengeInfo,
    plugin::{
        ChannelHealthSnapshot, ChannelOtpProvider, ChannelOutbound, ChannelPlugin, ChannelStatus,
        ChannelStreamOutbound,
    },
};

use crate::{
    bot, config::TelegramAccountConfig, outbound::TelegramOutbound, state::AccountStateMap,
};

/// Cache TTL for probe results (30 seconds).
const PROBE_CACHE_TTL: std::time::Duration = std::time::Duration::from_secs(30);

/// Telegram channel plugin.
pub struct TelegramPlugin {
    ...
}

impl TelegramPlugin {
    pub fn new() -> Self {

    pub fn with_message_log(mut self, log: Arc<dyn MessageLog>) -> Self {
    ...
}

    pub fn with_event_sink(mut self, sink: Arc<dyn ChannelEventSink>) -> Self {
    ...
}

    /// Get a shared reference to the outbound sender (for use outside the plugin).
    pub fn shared_outbound(&self) -> Arc<dyn ChannelOutbound> {
    ...
}

    /// Get a shared reference to streaming outbound sender.
    pub fn shared_stream_outbound(&self) -> Arc<dyn ChannelStreamOutbound> {
    ...
}

    /// List all active account IDs.
    pub fn account_ids(&self) -> Vec<String> {
    ...
}

    pub fn has_account(&self, account_id: &str) -> bool {
    ...
}

    /// Get the config for a specific account (serialized to JSON).
    pub fn account_config(&self, account_id: &str) -> Option<serde_json::Value> {
    ...
}

    /// Update the in-memory config for an account without restarting the
    /// polling loop.  Use for allowlist changes that don't need
    /// re-authentication or bot restart.
    pub fn update_account_config(
        &self,
        account_id: &str,
        config: serde_json::Value,
    ) -> ChannelResult<()> {
    ...
}

    /// List pending OTP challenges for a specific account.
    pub fn pending_otp_challenges(&self, account_id: &str) -> Vec<OtpChallengeInfo> {
    ...
}
}

impl Default for TelegramPlugin {
    fn default() -> Self {
}

#[async_trait]
impl ChannelPlugin for TelegramPlugin {
    fn id(&self) -> &str {

    fn name(&self) -> &str {
    ...
}

    async fn start_account(
        &mut self,
        account_id: &str,
        config: serde_json::Value,
    ) -> ChannelResult<()> {
    ...
}

    async fn stop_account(&mut self, account_id: &str) -> ChannelResult<()> {
    ...
}

    fn outbound(&self) -> Option<&dyn ChannelOutbound> {
    ...
}

    fn status(&self) -> Option<&dyn ChannelStatus> {
    ...
}

    fn has_account(&self, account_id: &str) -> bool {
    ...
}

    fn account_ids(&self) -> Vec<String> {
    ...
}

    fn account_config(&self, account_id: &str) -> Option<Box<dyn ChannelConfigView>> {
    ...
}

    fn account_config_json(&self, account_id: &str) -> Option<serde_json::Value> {
    ...
}

    fn update_account_config(
        &self,
        account_id: &str,
        config: serde_json::Value,
    ) -> ChannelResult<()> {
    ...
}

    fn shared_outbound(&self) -> Arc<dyn ChannelOutbound> {
    ...
}

    fn shared_stream_outbound(&self) -> Arc<dyn ChannelStreamOutbound> {
    ...
}

    fn as_otp_provider(&self) -> Option<&dyn ChannelOtpProvider> {
    ...
}
}

impl ChannelOtpProvider for TelegramPlugin {
    fn pending_otp_challenges(&self, account_id: &str) -> Vec<OtpChallengeInfo> {
}

#[async_trait]
impl ChannelStatus for TelegramPlugin {
    async fn probe(&self, account_id: &str) -> ChannelResult<ChannelHealthSnapshot> {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    /// Build a minimal `AccountState` for unit tests (no network calls).
    fn test_account_state(accounts: &AccountStateMap, cancel: CancellationToken) -> AccountState {
    ...
}

    #[test]
    fn update_account_config_updates_allowlist() {
    ...
}

    /// Security: `update_account_config` must NOT cancel the polling
    /// CancellationToken.  Cancelling it restarts the bot polling loop with
    /// offset 0, causing Telegram to re-deliver the OTP code message.  The
    /// re-delivered message would pass access control (user is now on the
    /// allowlist) and get forwarded to the LLM.
    #[test]
    fn security_update_config_does_not_cancel_polling() {
    ...
}

    /// Security: after a hot config update, the access control check must
    /// immediately reflect the new allowlist.  This simulates the exact
    /// sequence that happens during OTP self-approval.
    #[test]
    fn security_config_update_immediately_affects_access_control() {
    ...
}

    #[test]
    fn update_account_config_nonexistent_account_errors() {
    ...
}

    #[test]
    fn update_account_config_preserves_otp_state() {
    ...
}

    #[test]
    fn update_account_config_preserves_bot_token() {
    ...
}

    #[test]
    fn descriptor_coherence() {
    ...
}
}
