//! Lightweight WebSocket connection pool for the OpenAI Responses API.
//!
//! Reuses idle connections across consecutive `stream_with_tools_websocket`
//! calls.  Connections are bucketed by `(ws_url, key_hash)` so different
//! providers/keys never share a socket.  Stale entries are lazily evicted
//! on checkout — no background reaper task.

use std::{
    collections::HashMap,
    hash::{DefaultHasher, Hash, Hasher},
    sync::LazyLock,
};

use {
    tokio::{net::TcpStream, sync::Mutex},
    tokio_tungstenite::{MaybeTlsStream, WebSocketStream},
};

use tracing::debug;

// ── Pool constants (compile-time, not user-facing) ───────────────────

const MAX_IDLE_PER_KEY: usize = 4;
const MAX_IDLE_TOTAL: usize = 8;
/// Must sit below OpenAI's 60 s server-side idle timeout.
const IDLE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(55);
/// Rotate connections periodically regardless of activity.
const MAX_LIFETIME: std::time::Duration = std::time::Duration::from_secs(300);

// ── Types ────────────────────────────────────────────────────────────

/// Stream type returned by `tokio_tungstenite::connect_async`.
pub type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

/// Key used to bucket pooled connections.
#[derive(Clone, Hash, Eq, PartialEq)]
pub struct PoolKey {
    ...
}

impl PoolKey {
    /// Build a pool key from a WebSocket URL and an API key.
    ///
    /// The API key is hashed immediately — we never store the secret.
    pub fn new(ws_url: &str, api_key: &secrecy::Secret<String>) -> Self {
}

struct IdleConnection {
    ...
}

/// A bounded pool of idle WebSocket connections.
pub struct WsPool {
    ...
}

// ── Singleton ────────────────────────────────────────────────────────

/// Global shared pool (mirrors `shared_http_client()` pattern).
pub fn shared_ws_pool() -> &'static WsPool {
    ...
}

// ── Implementation ───────────────────────────────────────────────────

impl WsPool {
    fn new() -> Self {

    /// Try to reclaim an idle connection for the given key.
    ///
    /// Returns `None` when the pool has nothing valid.  Stale entries
    /// (idle-timeout or max-lifetime) are dropped automatically.
    pub async fn checkout(&self, key: &PoolKey) -> Option<(WsStream, std::time::Instant)> {
    ...
}

    /// Return a still-healthy connection for future reuse.
    ///
    /// The connection is silently dropped if it exceeds `MAX_LIFETIME`
    /// or the pool is already at capacity.
    pub async fn return_conn(
        &self,
        key: PoolKey,
        stream: WsStream,
        created_at: std::time::Instant,
    ) {
    ...
}

    /// Remove the single oldest (by `returned_at`) entry across all buckets.
    fn evict_oldest(map: &mut HashMap<PoolKey, Vec<IdleConnection>>) {
    ...
}
}

// ── Tests ────────────────────────────────────────────────────────────

#[cfg(test)]
#[allow(clippy::expect_used)]
mod tests {

    /// Server-side WS stream (plain TCP, no TLS wrapper).
    type ServerWsStream = WebSocketStream<TcpStream>;

    /// Spin up a local WS server and return a real `WsStream` client
    /// plus the server half for verification.
    async fn make_ws_pair() -> (WsStream, ServerWsStream) {
    ...
}

    fn test_key(url: &str, secret: &str) -> PoolKey {
    ...
}

    #[tokio::test]
    async fn checkout_empty_returns_none() {
    ...
}

    #[tokio::test]
    async fn return_then_checkout() {
    ...
}

    #[tokio::test]
    async fn idle_timeout_eviction() {
    ...
}

    #[tokio::test]
    async fn max_lifetime_eviction() {
    ...
}

    #[tokio::test]
    async fn max_idle_per_key() {
    ...
}

    #[tokio::test]
    async fn max_idle_total() {
    ...
}

    #[tokio::test]
    async fn different_keys_isolated() {
    ...
}

    #[tokio::test]
    async fn max_lifetime_rejected_on_return() {
    ...
}
}
