use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
};

use {
    moltis_channels::{ChannelEventSink, message_log::MessageLog},
    reqwest::Client,
    tokio::sync::Mutex,
};

use crate::{auth::CachedAccessToken, config::MsTeamsAccountConfig};

/// Shared account state map.
pub type AccountStateMap = Arc<RwLock<HashMap<String, AccountState>>>;

/// Per-account runtime state.
pub struct AccountState {
    ...
}
