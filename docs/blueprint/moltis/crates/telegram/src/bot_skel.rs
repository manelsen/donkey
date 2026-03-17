use std::sync::Arc;

use {
    secrecy::ExposeSecret,
    teloxide::{
        ApiError, RequestError,
        prelude::*,
        types::{AllowedUpdate, BotCommand, UpdateKind},
    },
    tokio_util::sync::CancellationToken,
    tracing::{debug, error, info, warn},
};

use moltis_channels::{ChannelEventSink, message_log::MessageLog};

use crate::{
    config::TelegramAccountConfig,
    handlers,
    outbound::TelegramOutbound,
    state::{AccountState, AccountStateMap},
};

/// Start polling for a single bot account.
///
/// Spawns a background task that processes updates until the returned
/// `CancellationToken` is cancelled.
pub async fn start_polling(
    account_id: String,
    config: TelegramAccountConfig,
    accounts: AccountStateMap,
    message_log: Option<Arc<dyn MessageLog>>,
    event_sink: Option<Arc<dyn ChannelEventSink>>,
) -> crate::Result<CancellationToken> {
    ...
}
