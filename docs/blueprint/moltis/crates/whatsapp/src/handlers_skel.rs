use std::sync::{Arc, atomic::Ordering};

use {
    tracing::{debug, info, warn},
    wacore::types::{events::Event, message::MessageInfo},
    wacore_binary::jid::{Jid, JidExt as _},
    waproto::whatsapp as wa,
    whatsapp_rust::client::Client,
};

use moltis_channels::{
    ChannelAttachment, ChannelEvent, ChannelMessageKind, ChannelMessageMeta, ChannelReplyTarget,
    ChannelType, message_log::MessageLogEntry,
};

use crate::{
    access::{self, AccessDenied},
    config::WhatsAppAccountConfig,
    otp::{OTP_CHALLENGE_MSG, OtpInitResult, OtpVerifyResult},
    state::{AccountState, AccountStateMap, has_bot_watermark},
};

fn mirror_connected(accounts: &AccountStateMap, account_id: &str, connected: bool) {
    ...
}

fn mirror_latest_qr(accounts: &AccountStateMap, account_id: &str, qr: Option<String>) {
    ...
}

fn current_config(
    accounts: &AccountStateMap,
    account_id: &str,
    fallback: &WhatsAppAccountConfig,
) -> WhatsAppAccountConfig {
    ...
}

/// Process an incoming whatsapp-rust event for the given account.
pub async fn handle_event(
    event: Event,
    client: Arc<Client>,
    state: Arc<AccountState>,
    accounts: AccountStateMap,
) {
    ...
}

async fn handle_message(
    msg: Box<wa::Message>,
    info: MessageInfo,
    client: &Client,
    state: &AccountState,
    accounts: &AccountStateMap,
) {
    ...
}

// ============================================================================
// Media handlers
// ============================================================================

/// Handle an inbound photo/image message: download, optimize, dispatch with attachment.
#[allow(clippy::too_many_arguments)]
async fn handle_photo(
    msg: &wa::Message,
    client: &Client,
    account_id: &str,
    reply_to: ChannelReplyTarget,
    meta: ChannelMessageMeta,
    _chat_jid: &Jid,
    state: &AccountState,
) {
    ...
}

/// Handle an inbound voice/audio message: download, transcribe (STT), dispatch as text.
#[allow(clippy::too_many_arguments)]
async fn handle_voice_audio(
    msg: &wa::Message,
    client: &Client,
    account_id: &str,
    kind: ChannelMessageKind,
    reply_to: ChannelReplyTarget,
    meta: ChannelMessageMeta,
    chat_jid: &Jid,
    state: &AccountState,
) {
    ...
}

/// Handle an inbound video message: download and dispatch with caption.
#[allow(clippy::too_many_arguments)]
async fn handle_video(
    msg: &wa::Message,
    _client: &Client,
    _account_id: &str,
    reply_to: ChannelReplyTarget,
    meta: ChannelMessageMeta,
    _chat_jid: &Jid,
    state: &AccountState,
) {
    ...
}

/// Handle an inbound document message: dispatch with caption.
#[allow(clippy::too_many_arguments)]
async fn handle_document(
    msg: &wa::Message,
    _client: &Client,
    account_id: &str,
    reply_to: ChannelReplyTarget,
    meta: ChannelMessageMeta,
    _chat_jid: &Jid,
    state: &AccountState,
) {
    ...
}

/// Handle an inbound location or live location message.
async fn handle_location(
    msg: &wa::Message,
    account_id: &str,
    reply_to: ChannelReplyTarget,
    meta: ChannelMessageMeta,
    chat_jid: &Jid,
    state: &AccountState,
) {
    ...
}

fn capitalize(s: &str) -> String {
    ...
}

fn is_owner_user(jid: &Jid, own_pn: Option<&Jid>, own_lid: Option<&Jid>) -> bool {
    ...
}

/// Classify the inbound message kind based on its content.
///
/// Media types take priority over text — an image with a caption is still `Photo`,
/// not `Text`. This ensures the media handler runs and can include the caption
/// alongside the attachment.
fn classify_message(msg: &wa::Message, text: &str) -> ChannelMessageKind {
    ...
}

/// Handle OTP challenge/verification flow for a non-allowlisted DM user.
///
/// Called when `dm_policy = Allowlist`, the peer is not on the allowlist, and
/// `otp_self_approval` is enabled.
#[allow(clippy::too_many_arguments)]
async fn handle_otp_flow(
    accounts: &AccountStateMap,
    account_id: &str,
    peer_id: &str,
    username: Option<&str>,
    sender_name: Option<&str>,
    body: &str,
    chat_jid: &Jid,
    state: &AccountState,
) {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn non_self_chat_from_me_is_not_treated_as_owner_self_chat() {
    ...
}

    #[test]
    fn sender_must_match_owner_when_is_from_me_is_false() {
    ...
}
}
