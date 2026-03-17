use std::sync::Arc;

use {
    async_trait::async_trait,
    moltis_tools::image_cache::ImageBuilder,
    tracing::{debug, error, info, warn},
};

use {
    moltis_channels::{
        ChannelAttachment, ChannelEvent, ChannelEventSink, ChannelMessageMeta, ChannelReplyTarget,
        Error as ChannelError, Result as ChannelResult,
    },
    moltis_sessions::metadata::SqliteSessionMetadata,
};

use crate::{
    broadcast::{BroadcastOpts, broadcast},
    state::GatewayState,
};

/// Default (deterministic) session key for a channel chat.
fn default_channel_session_key(target: &ChannelReplyTarget) -> String {
    ...
}

/// Resolve the active session key for a channel chat.
/// Uses the forward mapping table if an override exists, otherwise falls back
/// to the deterministic key.
async fn resolve_channel_session(
    target: &ChannelReplyTarget,
    metadata: &SqliteSessionMetadata,
) -> String {
    ...
}

fn slash_command_name(text: &str) -> Option<&str> {
    ...
}

fn is_channel_control_command_name(cmd: &str) -> bool {
    ...
}

fn rewrite_for_shell_mode(text: &str) -> Option<String> {
    ...
}

fn start_channel_typing_loop(
    state: &Arc<GatewayState>,
    reply_to: &ChannelReplyTarget,
) -> Option<tokio::sync::oneshot::Sender<()>> {
    ...
}

/// Broadcasts channel events over the gateway WebSocket.
///
/// Uses a deferred `OnceCell` reference so the sink can be created before
/// `GatewayState` exists (same pattern as cron callbacks).
pub struct GatewayChannelEventSink {
    ...
}

impl GatewayChannelEventSink {
    pub fn new(state: Arc<tokio::sync::OnceCell<Arc<GatewayState>>>) -> Self {
}

#[async_trait]
impl ChannelEventSink for GatewayChannelEventSink {
    async fn emit(&self, event: ChannelEvent) {
            #[cfg(feature = "whatsapp")]

    async fn dispatch_to_chat(
        &self,
        text: &str,
        reply_to: ChannelReplyTarget,
        meta: ChannelMessageMeta,
    ) {
    ...
}

    async fn request_disable_account(&self, channel_type: &str, account_id: &str, reason: &str) {
    ...
}

    async fn request_sender_approval(
        &self,
        _channel_type: &str,
        account_id: &str,
        identifier: &str,
    ) {
    ...
}

    async fn save_channel_voice(
        &self,
        audio_data: &[u8],
        filename: &str,
        reply_to: &ChannelReplyTarget,
    ) -> Option<String> {
    ...
}

    async fn transcribe_voice(&self, audio_data: &[u8], format: &str) -> ChannelResult<String> {
    ...
}

    async fn voice_stt_available(&self) -> bool {
    ...
}

    async fn dispatch_interaction(
        &self,
        callback_data: &str,
        reply_to: ChannelReplyTarget,
    ) -> ChannelResult<String> {
    ...
}

    async fn update_location(
        &self,
        reply_to: &ChannelReplyTarget,
        latitude: f64,
        longitude: f64,
    ) -> bool {
    ...
}

    async fn resolve_pending_location(
        &self,
        reply_to: &ChannelReplyTarget,
        latitude: f64,
        longitude: f64,
    ) -> bool {
    ...
}

    async fn dispatch_to_chat_with_attachments(
        &self,
        text: &str,
        attachments: Vec<ChannelAttachment>,
        reply_to: ChannelReplyTarget,
        meta: ChannelMessageMeta,
    ) {
    ...
}

    async fn dispatch_command(
        &self,
        command: &str,
        reply_to: ChannelReplyTarget,
    ) -> ChannelResult<String> {
    ...
}
}

/// Format a numbered model list, optionally filtered by provider.
///
/// Each line is: `N. DisplayName [provider] *` (where `*` marks the current model).
/// Uses the global index (across all models) so the switch command works with
/// the same numbering regardless of filtering.
fn format_model_list(
    models: &[serde_json::Value],
    current_model: Option<&str>,
    provider_filter: Option<&str>,
) -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
