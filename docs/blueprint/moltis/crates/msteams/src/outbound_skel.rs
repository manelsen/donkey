use {async_trait::async_trait, secrecy::ExposeSecret, tracing::debug};

use {
    moltis_channels::{
        Error as ChannelError, Result as ChannelResult,
        plugin::{ChannelOutbound, ChannelStreamOutbound, StreamEvent, StreamReceiver},
    },
    moltis_common::types::ReplyPayload,
};

use crate::{auth::get_access_token, config::MsTeamsAccountConfig, state::AccountStateMap};

/// Outbound sender for Microsoft Teams channel accounts.
pub struct MsTeamsOutbound {
    ...
}

struct AccountSnapshot {
    ...
}

impl MsTeamsOutbound {
    fn account_snapshot(
        &self,
        account_id: &str,
        conversation_id: &str,
    ) -> ChannelResult<AccountSnapshot> {

    async fn send_activity(
        &self,
        account_id: &str,
        conversation_id: &str,
        activity: serde_json::Value,
    ) -> ChannelResult<()> {
    ...
}
}

#[async_trait]
impl ChannelOutbound for MsTeamsOutbound {
    async fn send_text(
        &self,
        account_id: &str,
        to: &str,
        text: &str,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {

    async fn send_media(
        &self,
        account_id: &str,
        to: &str,
        payload: &ReplyPayload,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
    ...
}

    async fn send_typing(&self, account_id: &str, to: &str) -> ChannelResult<()> {
    ...
}

    async fn send_text_with_suffix(
        &self,
        account_id: &str,
        to: &str,
        text: &str,
        suffix_html: &str,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
    ...
}

    async fn send_html(
        &self,
        account_id: &str,
        to: &str,
        html: &str,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
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
    ) -> ChannelResult<()> {
    ...
}
}

#[async_trait]
impl ChannelStreamOutbound for MsTeamsOutbound {
    async fn send_stream(
        &self,
        account_id: &str,
        to: &str,
        reply_to: Option<&str>,
        mut stream: StreamReceiver,
    ) -> ChannelResult<()> {

    async fn is_stream_enabled(&self, _account_id: &str) -> bool {
    ...
}
}
