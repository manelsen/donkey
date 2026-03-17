pub use moltis_provider_setup::*;

use std::sync::Arc;

use crate::{
    broadcast::{BroadcastOpts, broadcast},
    state::GatewayState,
};

/// Gateway-side implementation of [`SetupBroadcaster`] that delegates to the
/// WebSocket broadcast mechanism.
pub struct GatewayBroadcaster {
    ...
}

#[async_trait::async_trait]
impl SetupBroadcaster for GatewayBroadcaster {
    async fn broadcast(&self, topic: &str, payload: serde_json::Value) {
}
