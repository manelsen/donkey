use {
    async_trait::async_trait,
    base64::Engine,
    tracing::{debug, info},
};

use {
    wacore::download::MediaType,
    wacore_binary::jid::Jid,
    waproto::whatsapp as wa,
    whatsapp_rust::{ChatStateType, upload::UploadResponse},
};

use {
    moltis_channels::{
        Result as ChannelResult,
        plugin::{ChannelOutbound, ChannelStreamOutbound, StreamEvent, StreamReceiver},
    },
    moltis_common::types::ReplyPayload,
};

use crate::state::{AccountStateMap, BOT_WATERMARK};

// ── Media helpers ────────────────────────────────────────────────────

/// Decode a `data:<mime>;base64,<payload>` URI into raw bytes.
fn decode_data_url(url: &str) -> ChannelResult<Vec<u8>> {
    ...
}

/// Map a MIME type to the WhatsApp `MediaType` used for encryption/upload.
fn mime_to_media_type(mime: &str) -> MediaType {
    ...
}

/// Build the `wa::Message` for a successfully uploaded media file.
fn build_media_message(
    mime: &str,
    caption: Option<String>,
    upload: &UploadResponse,
) -> wa::Message {
    ...
}

/// Outbound message sender for WhatsApp.
pub struct WhatsAppOutbound {
    ...
}

impl WhatsAppOutbound {
    fn get_client(
        &self,
        account_id: &str,
    ) -> ChannelResult<std::sync::Arc<whatsapp_rust::client::Client>> {

    /// Record a sent message ID for self-chat loop detection.
    fn record_sent_id(&self, account_id: &str, msg_id: &str) {
    ...
}
}

#[async_trait]
impl ChannelOutbound for WhatsAppOutbound {
    async fn send_text(
        &self,
        account_id: &str,
        to: &str,
        text: &str,
        _reply_to: Option<&str>,
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
}

#[async_trait]
impl ChannelStreamOutbound for WhatsAppOutbound {
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

#[cfg(test)]
mod tests {

    #[test]
    fn decode_data_url_no_comma_fails() {
    ...
}

    #[test]
    fn mime_to_media_type_mapping() {
    ...
}

    #[test]
    fn build_media_message_image() {
    ...
}

    #[test]
    fn build_media_message_video() {
    ...
}

    #[test]
    fn build_media_message_audio() {
    ...
}

    #[test]
    fn build_media_message_document_fallback() {
    ...
}
}
