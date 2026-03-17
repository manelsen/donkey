use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
};

use {
    moltis_channels::{ChannelEventSink, message_log::MessageLog},
    tokio_util::sync::CancellationToken,
};

use crate::config::SlackAccountConfig;

/// Shared account state map.
pub type AccountStateMap = Arc<RwLock<HashMap<String, AccountState>>>;

/// Per-account runtime state.
pub struct AccountState {
    ...
}
