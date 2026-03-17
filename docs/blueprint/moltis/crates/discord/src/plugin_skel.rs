use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
};

use {
    async_trait::async_trait,
    secrecy::ExposeSecret,
    tracing::{info, warn},
};

use moltis_channels::{
    ChannelConfigView, Error as ChannelError, Result as ChannelResult,
    message_log::MessageLog,
    plugin::{
        ChannelEventSink, ChannelHealthSnapshot, ChannelOutbound, ChannelPlugin, ChannelStatus,
        ChannelStreamOutbound, ChannelThreadContext,
    },
};

use moltis_channels::otp::OtpState;

use crate::{
    config::DiscordAccountConfig,
    handler::{Handler, required_intents},
    outbound::DiscordOutbound,
    state::{AccountState, AccountStateMap},
};

/// Discord channel plugin.
pub struct DiscordPlugin {
    ...
}

impl DiscordPlugin {
    pub fn new() -> Self {

    pub fn with_message_log(mut self, log: Arc<dyn MessageLog>) -> Self {
    ...
}

    pub fn with_event_sink(mut self, sink: Arc<dyn ChannelEventSink>) -> Self {
    ...
}

    pub fn shared_outbound(&self) -> Arc<dyn ChannelOutbound> {
    ...
}

    pub fn shared_stream_outbound(&self) -> Arc<dyn ChannelStreamOutbound> {
    ...
}

    pub fn account_ids(&self) -> Vec<String> {
    ...
}

    pub fn has_account(&self, account_id: &str) -> bool {
    ...
}

    pub fn account_config(&self, account_id: &str) -> Option<serde_json::Value> {
    ...
}

    pub fn update_account_config(
        &self,
        account_id: &str,
        config: serde_json::Value,
    ) -> ChannelResult<()> {
    ...
}
}

impl Default for DiscordPlugin {
    fn default() -> Self {
}

#[async_trait]
impl ChannelPlugin for DiscordPlugin {
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

    fn thread_context(&self) -> Option<&dyn ChannelThreadContext> {
    ...
}
}

#[async_trait]
impl ChannelStatus for DiscordPlugin {
    async fn probe(&self, account_id: &str) -> ChannelResult<ChannelHealthSnapshot> {
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn descriptor_coherence() {
    ...
}
}
