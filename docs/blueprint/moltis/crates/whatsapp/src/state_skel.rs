use std::{
    collections::{HashMap, VecDeque},
    sync::{
        Arc, Mutex, RwLock,
        atomic::{AtomicBool, Ordering},
    },
};

use {tokio::sync::Notify, tokio_util::sync::CancellationToken, whatsapp_rust::client::Client};

use moltis_channels::{ChannelEventSink, message_log::MessageLog};

use crate::{config::WhatsAppAccountConfig, otp::OtpState};

/// Maximum number of sent message IDs to track for self-chat loop detection.
const SENT_IDS_CAPACITY: usize = 256;

/// Invisible Unicode watermark appended to every bot-sent message.
///
/// A sequence of ZWJ (U+200D) and ZWNJ (U+200C) characters that is:
/// - Invisible to the user
/// - Preserved by WhatsApp (both are required for emoji/script rendering)
/// - Linguistically meaningless as an alternating pattern
///
/// Used as a secondary self-chat loop detection alongside message-ID tracking.
pub(crate) const BOT_WATERMARK: &str = "\u{200D}\u{200C}\u{200D}\u{200C}";

/// Shared account state map.
pub type AccountStateMap = Arc<RwLock<HashMap<String, AccountState>>>;

/// Synchronization primitive for graceful bot shutdown.
pub struct ShutdownState {
    ...
}

impl Default for ShutdownState {
    fn default() -> Self {
}

impl ShutdownState {
    pub fn new() -> Self {

    pub fn is_done(&self) -> bool {
    ...
}

    pub fn mark_done(&self) {
    ...
}

    pub async fn wait(&self) {
    ...
}
}

/// Per-account runtime state.
pub struct AccountState {
    ...
}

impl AccountState {
    /// Record a message ID that was sent by the bot, for self-chat loop detection.
    pub fn record_sent_id(&self, id: &str) {

    /// Check if a message ID was recently sent by the bot.
    pub fn was_sent_by_us(&self, id: &str) -> bool {
    ...
}

    /// Send a WhatsApp message and record its ID for self-chat loop detection.
    /// Appends an invisible watermark to text messages for secondary loop detection.
    pub async fn send_message(
        &self,
        to: wacore_binary::jid::Jid,
        mut msg: waproto::whatsapp::Message,
    ) -> crate::Result<()> {
    ...
}
}

/// Append the invisible bot watermark to a message's text content.
pub(crate) fn watermark_message(msg: &mut waproto::whatsapp::Message) {
    ...
}

/// Check if a message text contains the bot watermark.
pub(crate) fn has_bot_watermark(text: &str) -> bool {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    fn record(tracker: &Mutex<VecDeque<String>>, id: &str) {
    ...
}

    fn was_sent(tracker: &Mutex<VecDeque<String>>, id: &str) -> bool {
    ...
}

    #[test]
    fn sent_id_tracking_basic() {
    ...
}

    #[test]
    fn sent_id_tracking_evicts_oldest() {
    ...
}

    #[test]
    fn sent_id_tracking_no_false_positives() {
    ...
}

    #[test]
    fn watermark_appended_to_conversation() {
    ...
}

    #[test]
    fn watermark_appended_to_extended_text() {
    ...
}

    #[test]
    fn watermark_not_present_in_plain_text() {
    ...
}

    #[test]
    fn watermark_skips_message_without_text() {
    ...
}

    #[tokio::test]
    async fn shutdown_state_waits_for_completion() {
    ...
}
}
