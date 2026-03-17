use std::{
    collections::HashMap,
    sync::{Arc, Mutex, RwLock},
};

use {
    moltis_channels::{ChannelEventSink, message_log::MessageLog, otp::OtpState},
    serenity::all::UserId,
    tokio_util::sync::CancellationToken,
};

use crate::config::DiscordAccountConfig;

/// Shared account state map.
pub type AccountStateMap = Arc<RwLock<HashMap<String, AccountState>>>;

/// Per-account runtime state.
pub struct AccountState {
    ...
}
