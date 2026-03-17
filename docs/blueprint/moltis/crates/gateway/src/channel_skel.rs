use std::sync::Arc;

use {
    async_trait::async_trait,
    serde_json::Value,
    tracing::{error, info, warn},
};

use {
    moltis_channels::{
        ChannelOutbound, ChannelType,
        message_log::MessageLog,
        plugin::ChannelHealthSnapshot,
        registry::ChannelRegistry,
        store::{ChannelStore, StoredChannel},
    },
    moltis_sessions::metadata::SqliteSessionMetadata,
};

use crate::services::{ChannelService, ServiceError, ServiceResult};

fn unix_now() -> i64 {
    ...
}

/// Live channel service backed by the channel registry.
///
/// All per-channel dispatch is handled by the registry — no match arms needed.
pub struct LiveChannelService {
    ...
}

impl LiveChannelService {
    pub fn new(
        registry: Arc<ChannelRegistry>,
        outbound: Arc<dyn ChannelOutbound>,
        store: Arc<dyn ChannelStore>,
        message_log: Arc<dyn MessageLog>,
        session_metadata: Arc<SqliteSessionMetadata>,
    ) -> Self {

    /// Resolve channel type from explicit params, registry index, or store fallback.
    async fn resolve_channel_type(
        &self,
        params: &Value,
        account_id: &str,
        default_when_unknown: ChannelType,
    ) -> Result<ChannelType, String> {
    ...
}

    /// Build a status entry for a single channel account.
    async fn channel_status_entry(
        &self,
        channel_type: ChannelType,
        account_id: &str,
        snap: ChannelHealthSnapshot,
        config: Option<Value>,
    ) -> Value {
    ...
}
}

#[async_trait]
impl ChannelService for LiveChannelService {
    #[tracing::instrument(skip(self))]
    async fn status(&self) -> ServiceResult {

    #[tracing::instrument(skip(self, params))]
    async fn add(&self, params: Value) -> ServiceResult {
    ...
}

    #[tracing::instrument(skip(self, params))]
    async fn remove(&self, params: Value) -> ServiceResult {
    ...
}

    async fn logout(&self, params: Value) -> ServiceResult {
    ...
}

    #[tracing::instrument(skip(self, params))]
    async fn update(&self, params: Value) -> ServiceResult {
    ...
}

    async fn send(&self, params: Value) -> ServiceResult {
    ...
}

    async fn senders_list(&self, params: Value) -> ServiceResult {
    ...
}

    async fn sender_approve(&self, params: Value) -> ServiceResult {
    ...
}

    async fn sender_deny(&self, params: Value) -> ServiceResult {
    ...
}
}
