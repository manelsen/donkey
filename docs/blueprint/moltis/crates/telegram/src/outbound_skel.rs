use {
    async_trait::async_trait,
    base64::Engine,
    std::{future::Future, time::Duration},
    teloxide::{
        ApiError, RequestError,
        payloads::{SendLocationSetters, SendMessageSetters, SendVenueSetters},
        prelude::*,
        types::{ChatAction, ChatId, InputFile, MessageId, ParseMode, ReplyParameters},
    },
    tracing::{debug, info, warn},
};

use {
    moltis_channels::{
        Error as ChannelError, Result,
        plugin::{ChannelOutbound, ChannelStreamOutbound, StreamEvent, StreamReceiver},
    },
    moltis_common::types::ReplyPayload,
};

use crate::{
    config::StreamMode,
    markdown::{self, TELEGRAM_MAX_MESSAGE_LEN},
    state::AccountStateMap,
};

/// Outbound message sender for Telegram.
pub struct TelegramOutbound {
    ...
}

const TELEGRAM_RETRY_AFTER_MAX_RETRIES: usize = 4;

/// How often to re-send the typing indicator while waiting for stream events.
/// Telegram typing indicators expire after ~5 s; refresh well before that.
const TYPING_REFRESH_INTERVAL: Duration = Duration::from_secs(4);

#[derive(Debug, Clone, Copy)]
struct StreamSendConfig {
    ...
}

impl Default for StreamSendConfig {
    fn default() -> Self {
}

impl TelegramOutbound {
    fn get_bot(&self, account_id: &str) -> Result<Bot> {

    /// Build reply parameters only when `reply_to_message` is enabled for this account.
    fn reply_params(&self, account_id: &str, reply_to: Option<&str>) -> Option<ReplyParameters> {
    ...
}

    fn stream_send_config(&self, account_id: &str) -> StreamSendConfig {
    ...
}

    async fn send_chunk_with_fallback(
        &self,
        bot: &Bot,
        account_id: &str,
        to: &str,
        chat_id: ChatId,
        chunk: &str,
        reply_params: Option<&ReplyParameters>,
        silent: bool,
    ) -> Result<MessageId> {
    ...
}

    async fn edit_chunk_with_fallback(
        &self,
        bot: &Bot,
        account_id: &str,
        to: &str,
        chat_id: ChatId,
        message_id: MessageId,
        chunk: &str,
    ) -> Result<()> {
    ...
}

    async fn run_telegram_request_with_retry<T, F, Fut>(
        &self,
        account_id: &str,
        to: &str,
        operation: &'static str,
        mut request: F,
    ) -> std::result::Result<T, RequestError>
    where
        F: FnMut() -> Fut,
        Fut: Future<Output = std::result::Result<T, RequestError>>,
    {
        let mut retries = 0usize;

        loop {
            match request().await {
                Ok(value) => return Ok(value),
                Err(err) => {
                    let Some(wait) = retry_after_duration(&err) else {
                        return Err(err);
                    };

                    if retries >= TELEGRAM_RETRY_AFTER_MAX_RETRIES {
                        warn!(
                            account_id,
                            chat_id = to,
                            operation,
                            retries,
                            max_retries = TELEGRAM_RETRY_AFTER_MAX_RETRIES,
                            retry_after_secs = wait.as_secs(),
                            "telegram rate limit persisted after retries"
                        );
                        return Err(err);
                    }

                    retries += 1;
                    warn!(
                        account_id,
                        chat_id = to,
                        operation,
                        retries,
                        max_retries = TELEGRAM_RETRY_AFTER_MAX_RETRIES,
                        retry_after_secs = wait.as_secs(),
                        "telegram rate limited, waiting before retry"
                    );
                    tokio::time::sleep(wait).await;
                },
            }
        }
    }
}

/// Parse a platform message ID string into Telegram `ReplyParameters`.
/// Returns `None` if the string is not a valid i32 (Telegram message IDs are i32).
fn parse_reply_params(reply_to: Option<&str>) -> Option<ReplyParameters> {
    ...
}

fn retry_after_duration(error: &RequestError) -> Option<Duration> {
    ...
}

fn is_message_not_modified_error(error: &RequestError) -> bool {
    ...
}

fn telegram_html_to_plain_text(html: &str) -> String {
    ...
}

fn consume_plain_text_html_tag(input: &str) -> Option<(String, usize)> {
    ...
}

fn consume_html_entity(input: &str) -> Option<(String, usize)> {
    ...
}

fn is_plain_text_html_tag_name(tag_name: &str) -> bool {
    ...
}

fn is_plain_text_line_break_tag(tag_name: &str) -> bool {
    ...
}

fn decode_html_entity(entity: &str) -> Option<String> {
    ...
}

fn decode_numeric_html_entity(entity: &str) -> Option<String> {
    ...
}

trait RequestResultExt<T> {
    fn channel_context(self, context: &'static str) -> Result<T>;
}

impl<T> RequestResultExt<T> for std::result::Result<T, RequestError> {
    ...
}

fn has_reached_stream_min_initial_chars(accumulated: &str, min_initial_chars: usize) -> bool {
    ...
}

fn should_send_stream_completion_notification(
    notify_on_complete: bool,
    has_streamed_text: bool,
    sent_non_silent_completion_chunks: bool,
) -> bool {
    ...
}

#[async_trait]
impl ChannelOutbound for TelegramOutbound {
    async fn send_text(
        &self,
        account_id: &str,
        to: &str,
        text: &str,
        reply_to: Option<&str>,
    ) -> Result<()> {

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

    async fn send_typing(&self, account_id: &str, to: &str) -> Result<()> {
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

    async fn send_media(
        &self,
        account_id: &str,
        to: &str,
        payload: &ReplyPayload,
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
}

impl TelegramOutbound {
    /// Send a `ReplyPayload` — dispatches to text or media.
    pub async fn send_reply(&self, bot: &Bot, to: &str, payload: &ReplyPayload) -> Result<()> {
}

#[async_trait]
impl ChannelStreamOutbound for TelegramOutbound {
    async fn send_stream(
        &self,
        account_id: &str,
        to: &str,
        reply_to: Option<&str>,
        mut stream: StreamReceiver,
    ) -> Result<()> {

    async fn is_stream_enabled(&self, account_id: &str) -> bool {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    use crate::{config::TelegramAccountConfig, otp::OtpState, state::AccountState};

    #[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
    struct SendMessageRequest {
    ...
}

    #[derive(Debug, Serialize)]
    struct TelegramApiResponse {
    ...
}

    #[derive(Debug, Serialize)]
    struct TelegramMessageResult {
    ...
}

    #[derive(Debug, Serialize)]
    struct TelegramChat {
    ...
}

    #[derive(Clone)]
    struct MockTelegramApi {
    ...
}

    async fn send_message_handler(
        State(state): State<MockTelegramApi>,
        Json(body): Json<SendMessageRequest>,
    ) -> (StatusCode, Json<serde_json::Value>) {
    ...
}

    #[tokio::test]
    async fn send_location_unknown_account_returns_error() {
    ...
}

    #[test]
    fn retry_after_duration_extracts_wait() {
    ...
}

    #[test]
    fn retry_after_duration_ignores_other_errors() {
    ...
}

    #[test]
    fn telegram_html_to_plain_text_strips_tags_and_decodes_entities() {
    ...
}

    #[test]
    fn telegram_html_to_plain_text_decodes_numeric_entities() {
    ...
}

    #[test]
    fn telegram_html_to_plain_text_decodes_uppercase_hex_entities() {
    ...
}

    #[test]
    fn telegram_html_to_plain_text_preserves_non_tag_angle_bracket_text() {
    ...
}

    #[test]
    fn telegram_html_to_plain_text_preserves_preformatted_indentation() {
    ...
}

    #[test]
    fn is_message_not_modified_error_detects_variant() {
    ...
}

    #[test]
    fn is_message_not_modified_error_ignores_other_errors() {
    ...
}

    #[test]
    fn stream_min_initial_chars_uses_character_count() {
    ...
}

    #[test]
    fn stream_completion_notification_requires_opt_in() {
    ...
}

    #[test]
    fn stream_completion_notification_skips_when_no_text() {
    ...
}

    #[tokio::test]
    async fn send_html_fallback_sends_plain_text_without_raw_tags() {
    ...
}

    #[test]
    fn stream_completion_notification_skips_when_already_notified_by_chunks() {
    ...
}

    #[test]
    fn stream_completion_notification_enabled_when_needed() {
    ...
}
}
