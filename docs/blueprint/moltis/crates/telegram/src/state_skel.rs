use std::{
    collections::HashMap,
    sync::{Arc, Mutex, RwLock},
};

use tokio_util::sync::CancellationToken;

use moltis_channels::{ChannelEventSink, message_log::MessageLog};

use crate::{config::TelegramAccountConfig, otp::OtpState, outbound::TelegramOutbound};

/// Shared account state map.
pub type AccountStateMap = Arc<RwLock<HashMap<String, AccountState>>>;

/// Per-account runtime state.
pub struct AccountState {
    ...
}
