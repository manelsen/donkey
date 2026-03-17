use std::sync::Arc;

use {async_trait::async_trait, moltis_common::types::ReplyPayload, tokio::sync::mpsc};

use crate::{Error, Result, config_view::ChannelConfigView};

// ── Channel type enum ───────────────────────────────────────────────────────

/// Supported channel types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
#[non_exhaustive]
pub enum ChannelType {
    ...
}

impl ChannelType {
    /// Returns the channel type identifier as a string slice.
    pub fn as_str(&self) -> &'static str {

    /// Human-readable display name for UI labels.
    pub fn display_name(&self) -> &'static str {
    ...
}
}

impl std::fmt::Display for ChannelType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl std::str::FromStr for ChannelType {
    type Err = Error;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
}

impl ChannelType {
    /// All known channel types.
    pub const ALL: &[ChannelType] = &[
        Self::Telegram,
        Self::Whatsapp,
        Self::MsTeams,
        Self::Discord,
        Self::Slack,
    ];

    /// Returns the static descriptor for this channel type.
    #[must_use]
    pub fn descriptor(&self) -> ChannelDescriptor {
}

// ── Channel capabilities ──────────────────────────────────────────────────

/// How a channel receives inbound messages.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum InboundMode {
    ...
}

/// Static capability flags for a channel type.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct ChannelCapabilities {
    ...
}

/// Full descriptor for a channel type, including capabilities.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ChannelDescriptor {
    ...
}

// ── Channel events (pub/sub) ────────────────────────────────────────────────

/// Events emitted by channel plugins for real-time UI updates.
#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ChannelEvent {
    ...
}

/// Sink for channel events — the gateway provides the concrete implementation.
#[async_trait]
pub trait ChannelEventSink: Send + Sync {
    /// Broadcast a channel event for real-time UI updates.
    async fn emit(&self, event: ChannelEvent);

    /// Dispatch an inbound message to the main chat session (like sending
    /// from the web UI). The response is broadcast over WebSocket and
    /// routed back to the originating channel.
    async fn dispatch_to_chat(
        &self,
        text: &str,
        reply_to: ChannelReplyTarget,
        meta: ChannelMessageMeta,
    );

    /// Dispatch a slash command (e.g. "new", "clear", "compact", "context")
    /// and return a text result to send back to the channel.
    async fn dispatch_command(&self, command: &str, reply_to: ChannelReplyTarget)
    -> Result<String>;

    /// Request disabling a channel account due to a runtime error.
    ///
    /// This is used when the polling loop detects an unrecoverable error
    /// (e.g. another bot instance is running with the same token).
    async fn request_disable_account(&self, channel_type: &str, account_id: &str, reason: &str);

    /// Request adding a sender to the allowlist (OTP self-approval).
    ///
    /// The gateway implementation calls `sender_approve` to persist the change
    /// and restart the account.
    async fn request_sender_approval(
        &self,
        _channel_type: &str,
        _account_id: &str,
        _identifier: &str,
    ) {
    ...
}

    /// Save voice audio bytes to the session's media directory.
    ///
    /// Returns the saved filename on success, or `None` if saving is not
    /// available or fails. The gateway implementation resolves the session
    /// key from the reply target and delegates to `SessionStore::save_media`.
    async fn save_channel_voice(
        &self,
        _audio_data: &[u8],
        _filename: &str,
        _reply_to: &ChannelReplyTarget,
    ) -> Option<String> {
    ...
}

    /// Transcribe voice audio to text using the configured STT provider.
    ///
    /// Returns the transcribed text, or an error if transcription fails.
    /// The audio format is specified (e.g., "ogg", "mp3", "webm").
    async fn transcribe_voice(&self, audio_data: &[u8], format: &str) -> Result<String> {
    ...
}

    /// Whether voice STT is configured and available for channel audio messages.
    async fn voice_stt_available(&self) -> bool {
    ...
}

    /// Update the user's geolocation from a channel message (e.g. Telegram location share).
    ///
    /// Returns `true` if a pending tool-triggered location request was resolved.
    async fn update_location(
        &self,
        _reply_to: &ChannelReplyTarget,
        _latitude: f64,
        _longitude: f64,
    ) -> bool {
    ...
}

    /// Resolve a pending tool-triggered location request from channel text/link input.
    ///
    /// Unlike `update_location`, this should not update cached location state
    /// when there is no pending request. Returns `true` only when a pending
    /// request was found and resolved.
    async fn resolve_pending_location(
        &self,
        _reply_to: &ChannelReplyTarget,
        _latitude: f64,
        _longitude: f64,
    ) -> bool {
    ...
}

    /// Dispatch a button/menu interaction callback.
    ///
    /// Returns a response message to send back to the user.
    async fn dispatch_interaction(
        &self,
        _callback_data: &str,
        _reply_to: ChannelReplyTarget,
    ) -> Result<String> {
    ...
}

    /// Dispatch an inbound message with attachments (images, files) to the chat session.
    ///
    /// This is used when a channel message contains both text and media (e.g., a
    /// Telegram photo with a caption). The attachments are sent to the LLM as
    /// multimodal content.
    async fn dispatch_to_chat_with_attachments(
        &self,
        text: &str,
        attachments: Vec<ChannelAttachment>,
        reply_to: ChannelReplyTarget,
        meta: ChannelMessageMeta,
    ) {
    ...
}
}

/// Metadata about a channel message, used for UI display.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ChannelMessageMeta {
    ...
}

/// Inbound channel message media kind.
#[derive(Debug, Clone, Copy, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ChannelMessageKind {
    ...
}

/// An attachment (image, file) from a channel message.
#[derive(Debug, Clone)]
pub struct ChannelAttachment {
    ...
}

/// Where to send the LLM response back.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ChannelReplyTarget {
    ...
}

// ── Interactive messages ─────────────────────────────────────────────────────

/// A clickable button in a channel message.
#[derive(Debug, Clone)]
pub struct InteractiveButton {
    ...
}

/// Visual style for interactive buttons.
#[derive(Debug, Clone, Default)]
pub enum ButtonStyle {
    ...
}

/// A row of buttons.
pub type ButtonRow = Vec<InteractiveButton>;

/// A message with interactive button components.
#[derive(Debug, Clone)]
pub struct InteractiveMessage {
    ...
}

// ── Thread context ──────────────────────────────────────────────────────────

/// A single message from a thread conversation.
#[derive(Debug, Clone)]
pub struct ThreadMessage {
    ...
}

/// Fetch prior thread messages for context injection.
#[async_trait]
pub trait ChannelThreadContext: Send + Sync {
    /// Fetch up to `limit` messages from the given thread.
    async fn fetch_thread_messages(
        &self,
        account_id: &str,
        channel_id: &str,
        thread_id: &str,
        limit: usize,
    ) -> Result<Vec<ThreadMessage>>;
}

/// Core channel plugin trait. Each messaging platform implements this.
#[async_trait]
pub trait ChannelPlugin: Send + Sync {
    ...
}

/// OTP challenge provider for channels that support self-approval.
pub trait ChannelOtpProvider: Send + Sync {
    /// List pending OTP challenges for the given account.
    fn pending_otp_challenges(&self, account_id: &str) -> Vec<crate::otp::OtpChallengeInfo>;
}

/// Send messages to a channel.
///
/// `reply_to` is an optional platform-specific message ID that the outbound
/// message should thread as a reply to (e.g. Telegram `reply_to_message_id`).
#[async_trait]
pub trait ChannelOutbound: Send + Sync {
    ...
}

/// Probe channel account health.
#[async_trait]
pub trait ChannelStatus: Send + Sync {
    async fn probe(&self, account_id: &str) -> Result<ChannelHealthSnapshot>;
}

/// Channel health snapshot.
#[derive(Debug, Clone)]
pub struct ChannelHealthSnapshot {
    ...
}

/// Stream event for edit-in-place streaming.
#[derive(Debug, Clone)]
pub enum StreamEvent {
    ...
}

/// Receiver end of a stream channel.
pub type StreamReceiver = mpsc::Receiver<StreamEvent>;

/// Sender end of a stream channel.
pub type StreamSender = mpsc::Sender<StreamEvent>;

/// Streaming outbound — send responses via edit-in-place updates.
#[async_trait]
pub trait ChannelStreamOutbound: Send + Sync {
    /// Send a streaming response that updates a message in place.
    async fn send_stream(
        &self,
        account_id: &str,
        to: &str,
        reply_to: Option<&str>,
        stream: StreamReceiver,
    ) -> Result<()>;

    /// Whether streaming is enabled for this account.
    async fn is_stream_enabled(&self, _account_id: &str) -> bool {
    ...
}
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[tokio::test]
    async fn default_voice_stt_available_is_true() {
    ...
}

    #[tokio::test]
    async fn default_update_location_returns_false() {
    ...
}

    #[test]
    fn channel_type_whatsapp_roundtrip() {
    ...
}

    #[test]
    fn channel_type_serde_roundtrip() {
    ...
}

    #[test]
    fn channel_type_discord_roundtrip() {
    ...
}

    #[test]
    fn pairing_qr_code_event_serialization() {
    ...
}

    #[test]
    fn pairing_complete_event_serialization() {
    ...
}

    #[test]
    fn pairing_failed_event_serialization() {
    ...
}

    struct DummyOutbound;

    #[async_trait]
    impl ChannelOutbound for DummyOutbound {
        async fn send_text(
            &self,
            _account_id: &str,
            _to: &str,
            _text: &str,
            _reply_to: Option<&str>,
        ) -> Result<()> {

        async fn send_media(
            &self,
            _account_id: &str,
            _to: &str,
            _payload: &ReplyPayload,
            _reply_to: Option<&str>,
        ) -> Result<()> {
    ...
}
    }

    #[tokio::test]
    async fn default_send_location_is_noop() {
    ...
}

    #[tokio::test]
    async fn default_add_reaction_is_noop() {
    ...
}

    #[tokio::test]
    async fn default_remove_reaction_is_noop() {
    ...
}

    #[test]
    fn reaction_change_event_serialization() {
    ...
}

    #[test]
    fn channel_type_round_trip() {
    ...
}

    #[test]
    fn channel_type_from_str_invalid() {
    ...
}

    #[test]
    fn channel_type_serde_round_trip() {
    ...
}

    #[test]
    fn all_covers_every_variant() {
    ...
}

    #[test]
    fn descriptor_returns_correct_display_names() {
    ...
}

    #[test]
    fn descriptor_channel_type_matches() {
    ...
}

    #[test]
    fn descriptor_serialization_does_not_panic() {
    ...
}

    #[test]
    fn inbound_mode_serialization() {
    ...
}
}
