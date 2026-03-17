use std::time::Duration;

use {
    async_trait::async_trait,
    base64::Engine,
    tracing::{debug, info, warn},
};

use {
    moltis_channels::{
        Error as ChannelError, Result as ChannelResult,
        plugin::{
            ButtonStyle as ChannelButtonStyle, ChannelOutbound, ChannelStreamOutbound,
            ChannelThreadContext, InteractiveMessage, StreamEvent, StreamReceiver, ThreadMessage,
        },
    },
    moltis_common::types::ReplyPayload,
    serenity::all::{
        ButtonStyle as SerenityButtonStyle, ChannelId, CreateActionRow, CreateAttachment,
        CreateButton, CreateEmbed, CreateMessage, EditMessage, GetMessages, MessageId,
        ReactionType,
    },
};

use crate::{
    handler::{send_discord_message, send_discord_text},
    state::AccountStateMap,
};

// ── Constants ────────────────────────────────────────────────────────

/// Discord enforces a 2 000-character limit per message.
const DISCORD_MAX_MESSAGE_LEN: usize = 2000;
/// Discord embed description character limit.
const DISCORD_MAX_EMBED_DESCRIPTION_LEN: usize = 4096;

/// Minimum chars before the first message is sent during streaming.
const STREAM_MIN_INITIAL_CHARS: usize = 30;

/// Throttle interval between edit-in-place updates during streaming.
const STREAM_EDIT_THROTTLE: Duration = Duration::from_millis(500);

/// How often to re-send the typing indicator while waiting for stream events.
/// Discord typing indicators expire after ~10 s; refresh well before that.
const TYPING_REFRESH_INTERVAL: Duration = Duration::from_secs(8);

/// Send a lightweight preview first for larger images so users on slower
/// links get visual feedback quickly while the full upload is still in flight.
const DISCORD_IMAGE_PREVIEW_TRIGGER_BYTES: usize = 400 * 1024;
const DISCORD_IMAGE_PREVIEW_MAX_WIDTH: u32 = 1024;
const DISCORD_IMAGE_PREVIEW_MAX_HEIGHT: u32 = 1024;
const DISCORD_IMAGE_PREVIEW_TEXT: &str = "Preview while full image uploads...";

// ── HTML-to-Discord conversion ───────────────────────────────────────

/// Convert the HTML activity-log suffix (Telegram-flavoured) into Discord
/// markdown.  Handles `<blockquote expandable>`, `<b>`, `<i>`, `<code>`, and
/// HTML entities produced by `format_logbook_html`.
fn html_suffix_to_discord(html: &str) -> String {
    ...
}

/// Peek ahead to check if the next tag is `</blockquote>`.
fn peek_closing_blockquote(chars: &std::iter::Peekable<std::str::Chars<'_>>) -> bool {
    ...
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ActivityLogRender {
    ...
}

fn render_activity_log_for_discord(html: &str) -> Option<ActivityLogRender> {
    ...
}

// ── Media helpers ────────────────────────────────────────────────────

/// Decode a `data:<mime>;base64,<payload>` URI into raw bytes.
fn decode_data_url(url: &str) -> ChannelResult<Vec<u8>> {
    ...
}

/// Pick a sensible filename extension from a MIME type.
fn extension_for_mime(mime: &str) -> &'static str {
    ...
}

fn is_image_mime(mime: &str) -> bool {
    ...
}

fn build_upload_preview(data: &[u8], mime: &str) -> Option<(Vec<u8>, String)> {
    ...
}

// ── Outbound sender ──────────────────────────────────────────────────

/// Outbound sender for Discord channel accounts.
pub struct DiscordOutbound {
    ...
}

impl DiscordOutbound {
    fn resolve_http(
        &self,
        account_id: &str,
    ) -> ChannelResult<std::sync::Arc<serenity::http::Http>> {

    fn parse_channel_id(to: &str) -> ChannelResult<ChannelId> {
    ...
}

    /// Parse the `reply_to` message ID into a `MessageId` when `reply_to_message`
    /// is enabled for the account.
    fn resolve_reference(&self, account_id: &str, reply_to: Option<&str>) -> Option<MessageId> {
    ...
}

    /// Remove the ack reaction from the original message after the bot's
    /// response is complete.
    ///
    /// Accepts the already-resolved `http` handle to avoid re-acquiring the
    /// account state lock.
    async fn remove_ack_reaction(
        &self,
        account_id: &str,
        http: &serenity::http::Http,
        channel_id: ChannelId,
        reply_to: Option<&str>,
    ) {
    ...
}

    async fn send_activity_log_embed(
        &self,
        account_id: &str,
        http: &serenity::http::Http,
        channel_id: ChannelId,
        suffix_html: &str,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
    ...
}

    /// Inner implementation for `send_text_with_suffix` that does not handle
    /// ack reaction removal -- the caller is responsible for that.
    async fn send_text_with_suffix_inner(
        &self,
        account_id: &str,
        http: &serenity::http::Http,
        channel_id: ChannelId,
        text: &str,
        suffix_html: &str,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
    ...
}
}

#[async_trait]
impl ChannelOutbound for DiscordOutbound {
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

    async fn send_interactive(
        &self,
        account_id: &str,
        to: &str,
        message: &InteractiveMessage,
        reply_to: Option<&str>,
    ) -> ChannelResult<()> {
    ...
}
}

// ── Streaming ────────────────────────────────────────────────────────

/// Truncate a string to at most `max` characters on a char boundary.
fn truncate_at_char_boundary(s: &str, max: usize) -> &str {
    ...
}

#[async_trait]
impl ChannelStreamOutbound for DiscordOutbound {
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

// ── Thread context ──────────────────────────────────────────────────

#[async_trait]
impl ChannelThreadContext for DiscordOutbound {
    async fn fetch_thread_messages(
        &self,
        account_id: &str,
        _channel_id: &str,
        thread_id: &str,
        limit: usize,
    ) -> ChannelResult<Vec<ThreadMessage>> {
}

// ── Tests ────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
