//! GraphQL request context bridging to gateway state and services.

use std::sync::Arc;

use {moltis_service_traits::Services, serde_json::Value, tokio::sync::broadcast};

/// Context injected into every GraphQL resolver via `Context::data()`.
///
/// Holds an `Arc` to the broadcast sender so resolvers can subscribe to
/// real-time events, plus a direct reference to the service bundle so
/// resolvers can call domain services without RPC indirection.
pub struct GqlContext {
    ...
}

impl GqlContext {
    /// Subscribe to broadcast events.
    pub fn subscribe(&self) -> broadcast::Receiver<(String, Value)> {
}
