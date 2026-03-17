use std::time::Duration;

use {
    async_trait::async_trait,
    base64::Engine,
    secrecy::ExposeSecret,
    slack_morphism::prelude::*,
    tracing::{debug, warn},
};

use moltis_channels::{
    Error as ChannelError, Result as ChannelResult,
    plugin::{
        ButtonStyle, ChannelOutbound, ChannelStreamOutbound, ChannelThreadContext,
        InteractiveMessage, StreamEvent, StreamReceiver, ThreadMessage,
    },
};

use moltis_common::types::ReplyPayload;

use crate::{
    config::StreamMode,
    markdown::{SLACK_MAX_MESSAGE_LEN, chunk_message, markdown_to_slack},
    state::AccountStateMap,
};

/// Minimum chars before the first message is sent during streaming.
const STREAM_MIN_INITIAL_CHARS: usize = 30;

/// Slack outbound message sender.
pub struct SlackOutbound {
    ...
}

impl SlackOutbound {
    /// Get a Slack client session for the given account.
    fn get_session(
        &self,
        account_id: &str,
    ) -> ChannelResult<(SlackClient<SlackClientHyperHttpsConnector>, SlackApiToken)> {

    /// Get the thread_ts for reply threading.
    fn get_thread_ts(&self, account_id: &str, to: &str, reply_to: Option<&str>) -> Option<String> {
    ...
}

    /// Get the edit throttle duration for streaming.
    fn get_edit_throttle(&self, account_id: &str) -> Duration {
    ...
}

    /// Get the stream mode for the given account.
    fn get_stream_mode(&self, account_id: &str) -> StreamMode {
    ...
}

    /// Get the raw bot token string for API calls not covered by slack-morphism.
    fn get_bot_token(&self, account_id: &str) -> ChannelResult<String> {
    ...
}

    /// Native Slack streaming using chat.startStream/appendStream/stopStream.
    async fn send_stream_native(
        &self,
        account_id: &str,
        to: &str,
        thread_ts: Option<&str>,
        stream: &mut StreamReceiver,
    ) -> ChannelResult<()> {
    ...
}

    /// Edit-in-place streaming: post → throttled edits → final update.
    async fn send_stream_edit_in_place(
        &self,
        account_id: &str,
        to: &str,
        thread_ts: Option<&str>,
        stream: &mut StreamReceiver,
    ) -> ChannelResult<()> {
    ...
}
}

/// Post a message to a Slack channel.
async fn post_message(
    client: &SlackClient<SlackClientHyperHttpsConnector>,
    token: &SlackApiToken,
    channel: &str,
    text: &str,
    thread_ts: Option<&str>,
) -> ChannelResult<SlackTs> {
    ...
}

/// Update an existing message.
async fn update_message(
    client: &SlackClient<SlackClientHyperHttpsConnector>,
    token: &SlackApiToken,
    channel: &str,
    ts: &SlackTs,
    text: &str,
) -> ChannelResult<()> {
    ...
}

/// Decode a `data:<mime>;base64,<payload>` URI into raw bytes.
fn decode_data_url(url: &str) -> ChannelResult<(Vec<u8>, String)> {
    ...
}

/// Map MIME type to a file extension.
fn extension_for_mime(mime: &str) -> &'static str {
    ...
}

/// Upload a file to Slack using the V2 upload flow.
async fn upload_file(
    client: &SlackClient<SlackClientHyperHttpsConnector>,
    token: &SlackApiToken,
    channel: &str,
    filename: &str,
    content_type: &str,
    data: &[u8],
    caption: Option<&str>,
    thread_ts: Option<&str>,
) -> ChannelResult<()> {
    ...
}

/// Add or remove a reaction on a Slack message using the Web API.
async fn modify_reaction(
    client: &SlackClient<SlackClientHyperHttpsConnector>,
    token: &SlackApiToken,
    channel: &str,
    timestamp: &str,
    emoji: &str,
    add: bool,
) -> ChannelResult<()> {
    ...
}

#[async_trait]
impl ChannelOutbound for SlackOutbound {
    async fn send_text(
        &self,
        account_id: &str,
        to: &str,
        text: &str,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
        #[cfg(feature = "metrics")]

    async fn send_media(
        &self,
        account_id: &str,
        to: &str,
        payload: &ReplyPayload,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
    ...
}

    async fn send_typing(&self, _account_id: &str, _to: &str) -> ChannelResult<()> {
    ...
}

    async fn send_interactive(
        &self,
        account_id: &str,
        to: &str,
        message: &InteractiveMessage,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
    ...
}

    async fn add_reaction(
        &self,
        account_id: &str,
        channel_id: &str,
        message_id: &str,
        emoji: &str,
    ) -> ChannelResult<()> {
    ...
}

    async fn remove_reaction(
        &self,
        account_id: &str,
        channel_id: &str,
        message_id: &str,
        emoji: &str,
    ) -> ChannelResult<()> {
    ...
}
}

/// Start a native Slack stream via `chat.startStream`.
///
/// Returns `(stream_id, channel)` on success.
async fn start_native_stream(
    http: &reqwest::Client,
    bot_token: &str,
    channel: &str,
    thread_ts: Option<&str>,
) -> ChannelResult<String> {
    ...
}

/// Append text to a native Slack stream via `chat.appendStream`.
async fn append_native_stream(
    http: &reqwest::Client,
    bot_token: &str,
    stream_id: &str,
    text: &str,
) -> ChannelResult<()> {
    ...
}

/// Finalize a native Slack stream via `chat.stopStream`.
async fn stop_native_stream(
    http: &reqwest::Client,
    bot_token: &str,
    stream_id: &str,
) -> ChannelResult<()> {
    ...
}

#[async_trait]
impl ChannelStreamOutbound for SlackOutbound {
    async fn send_stream(
        &self,
        account_id: &str,
        to: &str,
        reply_to: Option<&str>,
        mut stream: StreamReceiver,
    ) -> ChannelResult<()> {

    async fn is_stream_enabled(&self, account_id: &str) -> bool {
    ...
}
}

#[async_trait]
impl ChannelThreadContext for SlackOutbound {
    async fn fetch_thread_messages(
        &self,
        account_id: &str,
        channel_id: &str,
        thread_id: &str,
        limit: usize,
    ) -> ChannelResult<Vec<ThreadMessage>> {
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn get_thread_ts_no_account() {
    ...
}

    #[test]
    fn decode_data_url_png() {
    ...
}

    #[test]
    fn decode_data_url_no_comma_fails() {
    ...
}

    #[test]
    fn extension_for_known_mimes() {
    ...
}
}
