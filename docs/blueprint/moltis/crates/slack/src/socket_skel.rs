use std::sync::Arc;

use {
    secrecy::ExposeSecret,
    slack_morphism::prelude::*,
    tracing::{debug, info, warn},
};

use moltis_channels::{
    config_view::ChannelConfigView,
    gating::{DmPolicy, GroupPolicy, is_allowed},
    message_log::MessageLogEntry,
    plugin::{
        ChannelEvent, ChannelMessageKind, ChannelMessageMeta, ChannelReplyTarget, ChannelType,
    },
};

use crate::{
    config::SlackAccountConfig,
    markdown::strip_mentions,
    state::{AccountState, AccountStateMap},
};

/// State stored in the Socket Mode listener for callback access.
#[derive(Clone)]
struct ListenerState {
    ...
}

/// Start Socket Mode for a single account.
///
/// Creates a `SlackClient`, calls `auth.test` to verify the bot token and
/// obtain the bot user ID, stores state, then spawns the socket listener.
pub async fn start_socket_mode(
    account_id: &str,
    config: SlackAccountConfig,
    accounts: AccountStateMap,
    message_log: Option<Arc<dyn moltis_channels::message_log::MessageLog>>,
    event_sink: Option<Arc<dyn moltis_channels::ChannelEventSink>>,
) -> moltis_channels::Result<()> {
    ...
}

/// Run the Socket Mode listener until cancelled.
async fn run_socket_listener(
    account_id: &str,
    client: Arc<SlackClient<SlackClientHyperHttpsConnector>>,
    app_token: SlackApiToken,
    accounts: AccountStateMap,
    cancel: tokio_util::sync::CancellationToken,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    ...
}

/// Error handler for Socket Mode.
fn error_handler(
    err: Box<dyn std::error::Error + Send + Sync>,
    _client: Arc<SlackClient<SlackClientHyperHttpsConnector>>,
    _states: SlackClientEventsUserState,
) -> HttpStatusCode {
    ...
}

/// Push events callback (messages, app_mention, etc.).
async fn push_events_callback(
    event: SlackPushEventCallback,
    _client: Arc<SlackClient<SlackClientHyperHttpsConnector>>,
    states: SlackClientEventsUserState,
) -> UserCallbackResult<()> {
    ...
}

/// Command events callback (slash commands).
async fn command_events_callback(
    event: SlackCommandEvent,
    _client: Arc<SlackClient<SlackClientHyperHttpsConnector>>,
    states: SlackClientEventsUserState,
) -> UserCallbackResult<SlackCommandEventResponse> {
    ...
}

/// Interaction events callback (block actions / button clicks).
async fn interaction_events_callback(
    event: SlackInteractionEvent,
    _client: Arc<SlackClient<SlackClientHyperHttpsConnector>>,
    states: SlackClientEventsUserState,
) -> UserCallbackResult<()> {
    ...
}

/// Handle a Slack message event.
pub(crate) async fn handle_message_event(
    account_id: &str,
    event: SlackMessageEvent,
    accounts: &AccountStateMap,
) {
    ...
}

/// Core inbound message processing.
///
/// Shared by message events, app_mention events, and webhook events.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn handle_inbound(
    account_id: &str,
    channel_id: &str,
    user_id: &str,
    text: &str,
    thread_ts: Option<String>,
    username: Option<String>,
    is_mention: bool,
    accounts: &AccountStateMap,
) {
    ...
}

/// Handle a reaction_added or reaction_removed event.
pub(crate) async fn handle_reaction_event(
    account_id: &str,
    user_id: &str,
    emoji: &str,
    item: &SlackReactionsItem,
    added: bool,
    accounts: &AccountStateMap,
) {
    ...
}

/// Check if a message should be processed based on access policies.
pub(crate) fn check_access(
    is_dm: bool,
    user_id: &str,
    channel_id: &str,
    dm_policy: &DmPolicy,
    group_policy: &GroupPolicy,
    user_allowlist: &[String],
    channel_allowlist: &[String],
) -> bool {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn dm_allowlist_requires_user() {
    ...
}

    #[test]
    fn dm_disabled_denies_all() {
    ...
}

    #[test]
    fn channel_open_allows_any() {
    ...
}

    #[test]
    fn channel_allowlist_requires_channel() {
    ...
}

    #[test]
    fn channel_disabled_denies_all() {
    ...
}
}
