use std::{
    collections::HashMap,
    sync::{Arc, RwLock as StdRwLock},
};

use {
    async_trait::async_trait,
    tokio::sync::RwLock,
    tracing::{instrument, warn},
};

use {
    super::plugin::{
        ChannelDescriptor, ChannelOutbound, ChannelPlugin, ChannelStreamOutbound, ChannelType,
        InteractiveMessage, StreamReceiver, ThreadMessage,
    },
    crate::{Error, Result, config_view::ChannelConfigView, plugin::ChannelHealthSnapshot},
};

use moltis_common::types::ReplyPayload;

#[cfg(feature = "metrics")]
use moltis_metrics::{channels as ch_metrics, gauge};

/// Production channel registry with O(1) account→plugin routing.
///
/// The registry owns all channel plugins and maintains an account index
/// for fast outbound routing. Lives in `crates/channels/` — no gateway
/// dependency.
///
/// Plugins are stored behind `tokio::sync::RwLock` because `start_account`
/// and `stop_account` are async (they may perform I/O during connection
/// setup). The account index uses `std::sync::RwLock` since it is never
/// held across await points.
pub struct ChannelRegistry {
    ...
}

impl Default for ChannelRegistry {
    fn default() -> Self {
}

impl ChannelRegistry {
    pub fn new() -> Self {

    /// Register a plugin by its `id()`.
    #[instrument(skip(self, plugin))]
    pub async fn register(&mut self, plugin: Arc<RwLock<dyn ChannelPlugin>>) {
    ...
}

    /// Get a plugin by channel type identifier.
    pub fn get(&self, channel_type: &str) -> Option<&Arc<RwLock<dyn ChannelPlugin>>> {
    ...
}

    /// List all registered channel type identifiers.
    pub fn list(&self) -> Vec<&str> {
    ...
}

    /// Start an account on the appropriate plugin and update the index.
    #[instrument(skip(self, config), fields(channel_type, account_id))]
    pub async fn start_account(
        &self,
        channel_type: &str,
        account_id: &str,
        config: serde_json::Value,
    ) -> Result<()> {
    ...
}

    /// Stop an account and remove it from the index.
    #[instrument(skip(self), fields(channel_type, account_id))]
    pub async fn stop_account(&self, channel_type: &str, account_id: &str) -> Result<()> {
    ...
}

    /// Resolve account_id → channel_type via the index.
    pub fn resolve_channel_type(&self, account_id: &str) -> Option<String> {
    ...
}

    /// Resolve an outbound sender for the given account.
    pub async fn resolve_outbound(&self, account_id: &str) -> Option<Arc<dyn ChannelOutbound>> {
    ...
}

    /// Resolve a streaming outbound sender for the given account.
    pub async fn resolve_stream(&self, account_id: &str) -> Option<Arc<dyn ChannelStreamOutbound>> {
    ...
}

    /// List all active accounts as `(channel_type, account_id)` pairs.
    pub fn all_accounts(&self) -> Vec<(String, String)> {
    ...
}

    /// Probe health of all accounts across all plugins.
    #[instrument(skip(self))]
    pub async fn status_all(&self) -> Vec<ChannelHealthSnapshot> {
    ...
}

    /// Get the typed config view for an account via the registry.
    pub async fn account_config(&self, account_id: &str) -> Option<Box<dyn ChannelConfigView>> {
    ...
}

    /// Get the raw JSON config for an account via the registry.
    pub async fn account_config_json(&self, account_id: &str) -> Option<serde_json::Value> {
    ...
}

    /// Fetch thread messages for context injection.
    ///
    /// Resolves the plugin for the given account and calls its thread context
    /// provider. Returns an empty vec if the plugin does not support threads.
    pub async fn fetch_thread_messages(
        &self,
        account_id: &str,
        channel_id: &str,
        thread_id: &str,
        limit: usize,
    ) -> Result<Vec<ThreadMessage>> {
    ...
}

    /// Update account config via the registry.
    pub async fn update_account_config(
        &self,
        account_id: &str,
        config: serde_json::Value,
    ) -> Result<()> {
    ...
}

    /// Returns descriptors for all registered channel types.
    ///
    /// Parses each registered plugin ID as a [`ChannelType`] and returns its
    /// static descriptor. Unknown plugin IDs are silently skipped.
    pub fn descriptors(&self) -> Vec<ChannelDescriptor> {
    ...
}
}

// ── RegistryOutboundRouter ──────────────────────────────────────────────────

/// Outbound router that delegates to the correct plugin via the registry index.
///
/// Replaces `MultiChannelOutbound` from the gateway. Lives in
/// `crates/channels/` — no gateway dependency.
pub struct RegistryOutboundRouter {
    ...
}

impl RegistryOutboundRouter {
    pub fn new(registry: Arc<ChannelRegistry>) -> Self {
}

#[async_trait]
impl ChannelOutbound for RegistryOutboundRouter {
    async fn send_text(
        &self,
        account_id: &str,
        to: &str,
        text: &str,
        reply_to: Option<&str>,
    ) -> Result<()> {

    async fn send_media(
        &self,
        account_id: &str,
        to: &str,
        payload: &ReplyPayload,
        reply_to: Option<&str>,
    ) -> Result<()> {
    ...
}

    async fn send_typing(&self, account_id: &str, to: &str) -> Result<()> {
    ...
}

    async fn send_text_with_suffix(
        &self,
        account_id: &str,
        to: &str,
        text: &str,
        suffix_html: &str,
        reply_to: Option<&str>,
    ) -> Result<()> {
    ...
}

    async fn send_html(
        &self,
        account_id: &str,
        to: &str,
        html: &str,
        reply_to: Option<&str>,
    ) -> Result<()> {
    ...
}

    async fn send_text_silent(
        &self,
        account_id: &str,
        to: &str,
        text: &str,
        reply_to: Option<&str>,
    ) -> Result<()> {
    ...
}

    async fn send_location(
        &self,
        account_id: &str,
        to: &str,
        latitude: f64,
        longitude: f64,
        title: Option<&str>,
        reply_to: Option<&str>,
    ) -> Result<()> {
    ...
}

    async fn send_interactive(
        &self,
        account_id: &str,
        to: &str,
        message: &InteractiveMessage,
        reply_to: Option<&str>,
    ) -> Result<()> {
    ...
}

    async fn add_reaction(
        &self,
        account_id: &str,
        channel_id: &str,
        message_id: &str,
        emoji: &str,
    ) -> Result<()> {
    ...
}

    async fn remove_reaction(
        &self,
        account_id: &str,
        channel_id: &str,
        message_id: &str,
        emoji: &str,
    ) -> Result<()> {
    ...
}
}

#[async_trait]
impl ChannelStreamOutbound for RegistryOutboundRouter {
    async fn send_stream(
        &self,
        account_id: &str,
        to: &str,
        reply_to: Option<&str>,
        stream: StreamReceiver,
    ) -> Result<()> {

    async fn is_stream_enabled(&self, account_id: &str) -> bool {
    ...
}
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    /// Minimal config view for testing contract tests.
    #[derive(Debug)]
    struct TestConfigView;

    impl ChannelConfigView for TestConfigView {
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

    /// Minimal plugin for testing.
    struct TestPlugin {
    ...
}

    impl TestPlugin {
        fn new(id: &str) -> Self {
    }

    #[async_trait]
    impl ChannelPlugin for TestPlugin {
        fn id(&self) -> &str {

        fn name(&self) -> &str {
    ...
}

        async fn start_account(
            &mut self,
            account_id: &str,
            config: serde_json::Value,
        ) -> Result<()> {
    ...
}

        async fn stop_account(&mut self, account_id: &str) -> Result<()> {
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

        fn update_account_config(
            &self,
            _account_id: &str,
            _config: serde_json::Value,
        ) -> Result<()> {
    ...
}

        fn shared_outbound(&self) -> Arc<dyn ChannelOutbound> {
    ...
}

        fn shared_stream_outbound(&self) -> Arc<dyn ChannelStreamOutbound> {
    ...
}
    }

    #[async_trait]
    impl ChannelStatus for TestPlugin {
        async fn probe(&self, account_id: &str) -> Result<ChannelHealthSnapshot> {
    }

    struct NullOutbound;

    #[async_trait]
    impl ChannelOutbound for NullOutbound {
        async fn send_text(&self, _: &str, _: &str, _: &str, _: Option<&str>) -> Result<()> {

        async fn send_media(
            &self,
            _: &str,
            _: &str,
            _: &ReplyPayload,
            _: Option<&str>,
        ) -> Result<()> {
    ...
}
    }

    struct NullStreamOutbound;

    #[async_trait]
    impl ChannelStreamOutbound for NullStreamOutbound {
        async fn send_stream(
            &self,
            _: &str,
            _: &str,
            _: Option<&str>,
            mut stream: StreamReceiver,
        ) -> Result<()> {
    }

    #[tokio::test]
    async fn register_and_list() {
    ...
}

    #[tokio::test]
    async fn start_and_resolve_account() {
    ...
}

    #[tokio::test]
    async fn stop_removes_from_index() {
    ...
}

    #[tokio::test]
    async fn duplicate_account_id_different_channel_rejected() {
    ...
}

    #[tokio::test]
    async fn same_account_id_same_channel_allowed() {
    ...
}

    #[tokio::test]
    async fn unknown_channel_type_errors() {
    ...
}

    #[tokio::test]
    async fn all_accounts_lists_pairs() {
    ...
}

    #[tokio::test]
    async fn outbound_router_delegates() {
    ...
}

    #[tokio::test]
    async fn outbound_router_unknown_account_errors() {
    ...
}

    #[tokio::test]
    async fn stream_router_delegates() {
    ...
}

    #[tokio::test]
    async fn stream_enabled_unknown_account() {
    ...
}

    #[tokio::test]
    async fn resolve_outbound_returns_none_for_unknown() {
    ...
}

    #[tokio::test]
    async fn resolve_stream_returns_none_for_unknown() {
    ...
}

    #[tokio::test]
    async fn descriptors_returns_registered_types() {
    ...
}

    #[test]
    fn descriptors_empty_registry() {
    ...
}

    // ── Contract tests ──────────────────────────────────────────────────────

    #[tokio::test]
    async fn contract_lifecycle_start_stop() {
    ...
}

    #[tokio::test]
    async fn contract_double_start_same_account() {
    ...
}

    #[tokio::test]
    async fn contract_stop_unknown_account() {
    ...
}

    #[tokio::test]
    async fn contract_config_view_after_start() {
    ...
}

    #[tokio::test]
    async fn contract_outbound_available_after_start() {
    ...
}

    #[tokio::test]
    async fn contract_shared_outbound_send_succeeds_after_start() {
    ...
}

    #[tokio::test]
    async fn contract_stream_completes_on_done_signal() {
    ...
}

    #[tokio::test]
    async fn contract_stream_completes_on_error_signal() {
    ...
}

    #[tokio::test]
    async fn contract_outbound_error_classification() {
    ...
}

    #[tokio::test]
    async fn contract_probe_unknown_account_returns_disconnected() {
    ...
}

    #[tokio::test]
    async fn contract_probe_started_account_returns_connected() {
    ...
}
}
