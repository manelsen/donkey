use std::sync::Arc;

use {
    tokio_util::sync::CancellationToken,
    tracing::{info, warn},
};

use moltis_channels::{ChannelEventSink, message_log::MessageLog};

use crate::{
    config::WhatsAppAccountConfig,
    handlers,
    state::{AccountState, AccountStateMap, ShutdownState},
};

/// Start a WhatsApp connection for the given account.
///
/// Builds the `Bot` with a persistent sled store, registers the event handler,
/// and spawns the event loop as a background tokio task. Session state persists
/// across restarts so the user does not need to re-scan the QR code.
pub async fn start_connection(
    account_id: String,
    config: WhatsAppAccountConfig,
    accounts: AccountStateMap,
    data_dir: std::path::PathBuf,
    message_log: Option<Arc<dyn MessageLog>>,
    event_sink: Option<Arc<dyn ChannelEventSink>>,
) -> crate::Result<()> {
    ...
}
