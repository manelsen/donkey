use {
    serenity::{
        all::{
            Context, CreateMessage, EventHandler, GatewayIntents, Interaction, Message, MessageId,
            ReactionType, Ready,
        },
        async_trait,
        gateway::ActivityData,
        model::user::OnlineStatus as SerenityOnlineStatus,
    },
    tracing::{debug, info, warn},
};

use crate::config::{
    ActivityType as CfgActivityType, DiscordAccountConfig, OnlineStatus as CfgOnlineStatus,
};

use crate::access;

use moltis_channels::{
    ChannelEvent, ChannelType,
    gating::DmPolicy,
    message_log::MessageLogEntry,
    otp::{OtpInitResult, OtpVerifyResult},
    plugin::{ChannelEventSink, ChannelMessageKind, ChannelMessageMeta, ChannelReplyTarget},
};

use crate::state::AccountStateMap;

/// Required gateway intents for the Discord bot.
pub fn required_intents() -> GatewayIntents {
    ...
}

/// Serenity event handler for a Discord bot account.
pub struct Handler {
    ...
}

fn unix_now() -> i64 {
    ...
}

fn unix_now_ms() -> u64 {
    ...
}

/// Discord snowflake epoch (2015-01-01T00:00:00.000Z) in Unix milliseconds.
const DISCORD_EPOCH_MS: u64 = 1_420_070_400_000;

fn discord_message_created_ms(message_id: MessageId) -> u64 {
    ...
}

fn is_valid_lat_lon(latitude: f64, longitude: f64) -> bool {
    ...
}

fn parse_coordinate_component(input: &str) -> Option<f64> {
    ...
}

fn parse_coordinate_pair(input: &str) -> Option<(f64, f64)> {
    ...
}

fn parse_coordinates_from_url(url_str: &str) -> Option<(f64, f64)> {
    ...
}

fn parse_map_link_coordinates(text: &str) -> Option<(f64, f64)> {
    ...
}

fn parse_plain_text_coordinates(text: &str) -> Option<(f64, f64)> {
    ...
}

fn extract_location_coordinates(text: &str) -> Option<(f64, f64)> {
    ...
}

/// Strip the bot mention (e.g. `<@123456789>`) from the beginning of a message.
pub fn strip_bot_mention(text: &str, bot_id: u64) -> String {
    ...
}

/// Set the bot's presence (activity + online status) from config.
fn set_bot_presence(ctx: &Context, account_id: &str, config: &DiscordAccountConfig) {
    ...
}

#[async_trait]
impl EventHandler for Handler {
    async fn message(&self, ctx: Context, msg: Message) {
        #[cfg(feature = "metrics")]

    async fn ready(&self, ctx: Context, ready: Ready) {
    ...
}

    async fn interaction_create(&self, ctx: Context, interaction: Interaction) {
    ...
}
}

/// OTP challenge message sent to non-allowlisted DM users.
///
/// SECURITY: This message must NEVER contain the OTP code. The code is only
/// visible to the admin in the web UI under Channels → Senders.
const OTP_CHALLENGE_MSG: &str = "To use this bot, please enter the verification code.\n\nAsk the bot owner for the code \u{2014} it is visible in the web UI under **Channels \u{2192} Senders**.\n\nThe code expires in 5 minutes.";

/// Check if a message body looks like a 6-digit OTP code.
fn looks_like_otp_code(text: &str) -> bool {
    ...
}

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
    body: &str,
    channel_id: serenity::all::ChannelId,
    event_sink: Option<&dyn ChannelEventSink>,
    ctx: &Context,
) {
    ...
}

/// Simple send using the Context's http — used for OTP messages where we don't
/// have the full Http handle from state.
async fn send_discord_text_simple(
    ctx: &Context,
    channel_id: serenity::all::ChannelId,
    text: &str,
) -> Result<(), String> {
    ...
}

/// Send a text message to a Discord channel, chunking at the 2000-character limit.
pub async fn send_discord_text(
    http: &serenity::http::Http,
    channel_id: serenity::all::ChannelId,
    text: &str,
) -> Result<(), String> {
    ...
}

/// Send a text message and return the last sent `Message` (needed for
/// edit-in-place streaming).
///
/// When `reference` is `Some`, the first chunk is sent as a Discord reply
/// to that message (using `reference_message`).
pub async fn send_discord_message(
    http: &serenity::http::Http,
    channel_id: serenity::all::ChannelId,
    text: &str,
    reference: Option<MessageId>,
) -> Result<Message, String> {
    ...
}

/// Split a message into chunks of at most `max_len` characters.
///
/// The chunker is markdown-aware: it avoids splitting inside fenced code blocks
/// (triple-backtick regions) so that Discord renders them correctly.
fn chunk_message(text: &str, max_len: usize) -> Vec<&str> {
    ...
}

/// Find the best position to split `text` within `max_len` bytes.
///
/// Avoids splitting inside fenced code blocks. Prefers newlines outside of code
/// fences, falls back to `max_len` if no better boundary is found.
fn find_split_point(text: &str, max_len: usize) -> usize {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn strip_mention_no_match() {
    ...
}

    #[test]
    fn strip_mention_different_bot() {
    ...
}

    #[test]
    fn extract_location_coordinates_from_plain_pair() {
    ...
}

    #[test]
    fn extract_location_coordinates_from_google_query() {
    ...
}

    #[test]
    fn extract_location_coordinates_from_google_path_marker() {
    ...
}

    #[test]
    fn extract_location_coordinates_from_apple_maps() {
    ...
}

    #[test]
    fn extract_location_coordinates_rejects_non_location_text() {
    ...
}

    #[test]
    fn chunk_short_message() {
    ...
}

    #[test]
    fn chunk_long_message() {
    ...
}

    #[test]
    fn chunk_splits_at_newline() {
    ...
}

    #[test]
    fn chunk_avoids_splitting_inside_code_fence() {
    ...
}

    /// Security: the OTP challenge message sent to the Discord user must
    /// NEVER contain the verification code. The code should only be visible
    /// to the admin in the web UI. If this test fails, unauthenticated users
    /// can self-approve without admin involvement.
    #[test]
    fn security_otp_challenge_message_does_not_contain_code() {
    ...
}

    #[test]
    fn chunk_code_fence_too_large_falls_back() {
    ...
}

    // ── OTP code detection tests ─────────────────────────────────────

    #[test]
    fn looks_like_otp_code_valid() {
    ...
}

    #[test]
    fn looks_like_otp_code_rejects_non_codes() {
    ...
}

    #[test]
    fn looks_like_otp_code_rejects_unicode_digits() {
    ...
}

    // ── OTP message security tests ───────────────────────────────────

    #[test]
    fn security_otp_message_has_no_format_placeholders() {
    ...
}

    #[test]
    fn security_otp_message_points_to_web_ui() {
    ...
}

    #[test]
    fn otp_message_uses_discord_markdown_not_html() {
    ...
}

    #[test]
    fn otp_message_mentions_expiry() {
    ...
}

    // ── Presence config mapping tests ────────────────────────────────

    #[test]
    fn required_intents_includes_reactions() {
    ...
}

    #[test]
    fn required_intents_includes_message_content() {
    ...
}

    #[test]
    fn strip_mention_with_leading_whitespace() {
    ...
}

    #[test]
    fn strip_mention_only_mention() {
    ...
}

    #[test]
    fn discord_message_created_ms_from_snowflake() {
    ...
}
}
