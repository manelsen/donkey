use std::sync::Arc;

use {
    teloxide::{
        payloads::SendMessageSetters,
        prelude::*,
        types::{
            CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, MediaKind, MessageKind,
            ParseMode,
        },
    },
    tracing::{debug, info, warn},
};

use {
    moltis_channels::{
        ChannelAttachment, ChannelEvent, ChannelMessageKind, ChannelMessageMeta, ChannelOutbound,
        ChannelReplyTarget, ChannelType, message_log::MessageLogEntry,
    },
    moltis_common::types::ChatType,
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram, telegram as tg_metrics};

use crate::{
    access::{self, AccessDenied},
    otp::{OtpInitResult, OtpVerifyResult},
    state::AccountStateMap,
};

/// Shared context injected into teloxide's dispatcher.
#[derive(Clone)]
pub struct HandlerContext {
    ...
}

/// Build the teloxide update handler.
pub fn build_handler() -> Handler<
    'static,
    DependencyMap,
    Result<(), Box<dyn std::error::Error + Send + Sync>>,
    teloxide::dispatching::DpHandlerDescription,
> {
    ...
}

/// Handle a single inbound Telegram message (called from manual polling loop).
pub async fn handle_message_direct(
    msg: Message,
    bot: &Bot,
    account_id: &str,
    accounts: &AccountStateMap,
) -> crate::Result<()> {
    ...
}

fn should_intercept_slash_command(cmd: &str, cmd_text: &str) -> bool {
    ...
}

/// OTP challenge message sent to the Telegram user.
///
/// **Security invariant:** this message must NEVER contain the actual
/// verification code.  The code is only visible to the bot owner in the
/// web UI (Channels → Senders).  Leaking it here would let any
/// unauthenticated user self-approve without admin awareness.
pub(crate) const OTP_CHALLENGE_MSG: &str = "To use this bot, please enter the verification code.\n\nAsk the bot owner for the code \u{2014} it is visible in the web UI under <b>Channels \u{2192} Senders</b>.\n\nThe code expires in 5 minutes.";

/// Handle OTP challenge/verification flow for a non-allowlisted DM user.
///
/// Called when `dm_policy = Allowlist`, the peer is not on the allowlist, and
/// `otp_self_approval` is enabled. Manages the full lifecycle:
/// - First message: issue a 6-digit OTP challenge
/// - Code reply: verify and auto-approve on match
/// - Non-code messages while pending: silently ignored (flood protection)
#[allow(clippy::too_many_arguments)]
async fn handle_otp_flow(
    accounts: &AccountStateMap,
    account_id: &str,
    peer_id: &str,
    username: Option<&str>,
    sender_name: Option<&str>,
    text: Option<&str>,
    msg: &Message,
    event_sink: Option<&dyn moltis_channels::ChannelEventSink>,
) {
    ...
}

/// Handle an edited message — only processes live location updates.
///
/// Telegram sends live location updates as `EditedMessage` with `MediaKind::Location`.
/// We silently update the cached location without dispatching to the LLM or
/// re-checking access (the user was already approved on the initial share).
pub async fn handle_edited_location(
    msg: Message,
    account_id: &str,
    accounts: &AccountStateMap,
) -> crate::Result<()> {
    ...
}

/// Handle a single inbound Telegram message (teloxide dispatcher endpoint).
async fn handle_message(
    msg: Message,
    bot: Bot,
    ctx: Arc<HandlerContext>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    ...
}

/// Send a sessions list as an inline keyboard.
///
/// Parses the text response from `dispatch_command("sessions")` to extract
/// session labels, then sends an inline keyboard with one button per session.
async fn send_sessions_keyboard(bot: &Bot, chat_id: &str, sessions_text: &str) {
    ...
}

/// Send agent selection as an inline keyboard.
///
/// Parses numbered lines like:
/// `1. 🤖 Main [main] (default) *`
async fn send_agent_keyboard(bot: &Bot, chat_id: &str, agents_text: &str) {
    ...
}

/// Send context info as a formatted HTML card with blockquote sections.
///
/// Parses the markdown context response from `dispatch_command("context")`
/// and renders it as a structured Telegram HTML message.
async fn send_context_card(bot: &Bot, chat_id: &str, context_text: &str) {
    ...
}

/// Send model selection as an inline keyboard.
///
/// If the response starts with `providers:`, show a provider picker first.
/// Otherwise show the model list directly.
async fn send_model_keyboard(bot: &Bot, chat_id: &str, text: &str) {
    ...
}

/// Send sandbox status with toggle button and image picker.
///
/// First line is `status:on` or `status:off`. Remaining lines are numbered
/// images, with `*` marking the current one.
async fn send_sandbox_keyboard(bot: &Bot, chat_id: &str, text: &str) {
    ...
}

fn escape_html_simple(s: &str) -> String {
    ...
}

/// Handle a Telegram callback query (inline keyboard button press).
pub async fn handle_callback_query(
    query: CallbackQuery,
    _bot: &Bot,
    account_id: &str,
    accounts: &AccountStateMap,
) -> crate::Result<()> {
    ...
}

/// Extract text content from a message.
fn extract_text(msg: &Message) -> Option<String> {
    ...
}

/// Check if the message contains media (photo, document, etc.).
fn has_media(msg: &Message) -> bool {
    ...
}

/// Extract a file ID reference from a message for later download.
#[allow(dead_code)]
fn extract_media_url(msg: &Message) -> Option<String> {
    ...
}

/// Voice/audio file info for transcription.
struct VoiceFileInfo {
    ...
}

/// Extract voice or audio file info from a message.
fn extract_voice_file(msg: &Message) -> Option<VoiceFileInfo> {
    ...
}

/// Photo file info for vision.
struct PhotoFileInfo {
    ...
}

/// Extract photo file info from a message.
/// Returns the largest photo size for best quality.
fn extract_photo_file(msg: &Message) -> Option<PhotoFileInfo> {
    ...
}

/// Extracted location info from a Telegram message.
struct LocationInfo {
    ...
}

/// Extract location coordinates from a message.
fn extract_location(msg: &Message) -> Option<LocationInfo> {
    ...
}

/// Describe a media kind for logging purposes.
fn describe_media_kind(msg: &Message) -> Option<&'static str> {
    ...
}

fn message_kind(msg: &Message) -> Option<ChannelMessageKind> {
    ...
}

trait ToChannelMessageKind {
    fn to_channel_message_kind(&self) -> ChannelMessageKind;
}

impl ToChannelMessageKind for MediaKind {
    ...
}

/// Download a file from Telegram by file ID.
async fn download_telegram_file(bot: &Bot, file_id: &str) -> crate::Result<Vec<u8>> {
    ...
}

/// Classify the chat type.
fn classify_chat(msg: &Message) -> (ChatType, Option<String>) {
    ...
}

/// Check if the bot was @mentioned in the message.
fn check_bot_mentioned(msg: &Message, bot_username: Option<&str>) -> bool {
    ...
}

/// Build a session key.
#[allow(dead_code)]
fn build_session_key(
    account_id: &str,
    chat_type: &ChatType,
    peer_id: &str,
    group_id: Option<&str>,
) -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    use {
        async_trait::async_trait,
        axum::{Json, Router, body::Bytes, extract::State, http::Uri, routing::post},
        moltis_channels::{
            ChannelEvent, ChannelEventSink, ChannelMessageMeta, ChannelReplyTarget,
            Error as ChannelError, Result, gating::DmPolicy,
        },
        secrecy::Secret,
        serde::{Deserialize, Serialize},
        serde_json::json,
        tokio::sync::oneshot,
        tokio_util::sync::CancellationToken,
    };

    use crate::{
        config::TelegramAccountConfig,
        otp::OtpState,
        outbound::TelegramOutbound,
        state::{AccountState, AccountStateMap},
    };

    #[derive(Debug, Clone, PartialEq, Eq)]
    enum TelegramApiMethod {
    ...
}

    impl TelegramApiMethod {
        fn from_path(path: &str) -> Self {
    }

    #[derive(Debug, Clone)]
    enum CapturedTelegramRequest {
    ...
}

    #[derive(Debug, Clone, Deserialize)]
    struct SendMessageRequest {
    ...
}

    #[derive(Debug, Clone, Deserialize)]
    struct SendChatActionRequest {
    ...
}

    #[derive(Debug, Serialize)]
    struct TelegramApiResponse {
    ...
}

    #[derive(Debug, Serialize)]
    #[serde(untagged)]
    enum TelegramApiResult {
    ...
}

    #[derive(Debug, Serialize)]
    struct TelegramFileResult {
    ...
}

    #[derive(Debug, Serialize)]
    struct TelegramChat {
    ...
}

    #[derive(Debug, Serialize)]
    struct TelegramMessageResult {
    ...
}

    #[derive(Clone)]
    struct MockTelegramApi {
    ...
}

    async fn telegram_api_handler(
        State(state): State<MockTelegramApi>,
        uri: Uri,
        body: Bytes,
    ) -> Json<TelegramApiResponse> {
    ...
}

    #[derive(Default)]
    struct MockSink {
    ...
}

    impl MockSink {
        fn with_stt(transcription: Result<String>) -> Self {
    }

    #[async_trait]
    impl ChannelEventSink for MockSink {
        async fn emit(&self, _event: ChannelEvent) {
        async fn dispatch_to_chat(
            &self,
            text: &str,
            _reply_to: ChannelReplyTarget,
            _meta: ChannelMessageMeta,
        ) {
    ...
}

        async fn dispatch_command(
            &self,
            _command: &str,
            _reply_to: ChannelReplyTarget,
        ) -> Result<String> {
    ...
}

        async fn request_disable_account(
            &self,
            _channel_type: &str,
            _account_id: &str,
            _reason: &str,
        ) {
    ...
}

        async fn transcribe_voice(&self, _audio_data: &[u8], _format: &str) -> Result<String> {
    ...
}

        async fn voice_stt_available(&self) -> bool {
    ...
}
    }

    #[test]
    fn session_key_dm() {
    ...
}

    #[test]
    fn session_key_group() {
    ...
}

    #[test]
    fn intercepts_shell_mode_control_commands_only() {
    ...
}

    #[test]
    fn shell_command_payloads_are_not_intercepted() {
    ...
}

    /// Security: the OTP challenge message sent to the Telegram user must
    /// NEVER contain the verification code.  The code should only be visible
    /// to the admin in the web UI.  If this test fails, unauthenticated users
    /// can self-approve without admin involvement.
    #[test]
    fn security_otp_challenge_message_does_not_contain_code() {
    ...
}

    #[test]
    fn voice_messages_are_marked_with_voice_message_kind() {
    ...
}

    #[tokio::test]
    async fn voice_not_configured_replies_with_setup_hint_and_skips_dispatch() {
    ...
}

    /// Regression test: when STT is available but transcription returns an empty
    /// string (e.g. noisy environment), the voice message must still be
    /// dispatched to chat and the audio saved, rather than silently dropped.
    #[tokio::test]
    async fn voice_empty_transcription_still_dispatches_to_chat() {
    ...
}

    #[test]
    fn extract_location_from_message() {
    ...
}

    #[test]
    fn extract_location_returns_none_for_text() {
    ...
}

    #[test]
    fn location_messages_are_marked_with_location_message_kind() {
    ...
}

    #[test]
    fn extract_location_detects_live_period() {
    ...
}
}
