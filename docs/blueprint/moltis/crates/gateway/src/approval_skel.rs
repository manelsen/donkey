//! Live approval service and broadcaster for the gateway.

use std::sync::Arc;

use {async_trait::async_trait, serde_json::Value, tracing::info};

use moltis_tools::{
    approval::{ApprovalDecision, ApprovalManager},
    exec::ApprovalBroadcaster,
};

use crate::{
    broadcast::{BroadcastOpts, broadcast},
    services::{ExecApprovalService, ServiceResult},
    state::GatewayState,
};

/// Live approval service backed by an `ApprovalManager`.
pub struct LiveExecApprovalService {
    ...
}

impl LiveExecApprovalService {
    pub fn new(manager: Arc<ApprovalManager>) -> Self {
}

#[async_trait]
impl ExecApprovalService for LiveExecApprovalService {
    async fn get(&self) -> ServiceResult {

    async fn set(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn node_get(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn node_set(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn request(&self, _params: Value) -> ServiceResult {
    ...
}

    async fn resolve(&self, params: Value) -> ServiceResult {
    ...
}
}

/// Broadcasts approval requests to connected WebSocket clients.
pub struct GatewayApprovalBroadcaster {
    ...
}

impl GatewayApprovalBroadcaster {
    pub fn new(state: Arc<GatewayState>) -> Self {
}

#[async_trait]
impl ApprovalBroadcaster for GatewayApprovalBroadcaster {
    async fn broadcast_request(&self, request_id: &str, command: &str) -> moltis_tools::Result<()> {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_live_service_get() {
    ...
}
}
