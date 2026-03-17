use std::{
    collections::{HashMap, HashSet, VecDeque},
    sync::{
        Arc,
        atomic::{AtomicU64, AtomicUsize, Ordering},
    },
    time::Instant,
};

#[cfg(feature = "graphql")]
use std::sync::atomic::AtomicBool;

#[cfg(feature = "metrics")]
use moltis_metrics::MetricsHandle;

// Re-export for use by other modules
#[cfg(feature = "metrics")]
pub use moltis_metrics::{MetricsHistoryPoint, MetricsStore, ProviderTokens, SqliteMetricsStore};

use tokio::sync::{RwLock, mpsc, oneshot};

// ── Metrics history ──────────────────────────────────────────────────────────

/// Ring buffer for storing metrics history.
#[cfg(feature = "metrics")]
pub struct MetricsHistory {
    ...
}

#[cfg(feature = "metrics")]
impl MetricsHistory {
    /// Create a new history buffer with the given capacity.
    /// Default: 360 points = 3 hours at 30-second intervals.
    pub fn new(max_points: usize) -> Self {

    /// Add a new data point, evicting the oldest if at capacity.
    pub fn push(&mut self, point: MetricsHistoryPoint) {
    ...
}

    /// Iterate over all stored points (oldest to newest).
    pub fn iter(&self) -> impl Iterator<Item = &MetricsHistoryPoint> {
    ...
}

    /// Return the configured maximum capacity.
    pub fn capacity(&self) -> usize {
    ...
}
}

#[cfg(feature = "metrics")]
impl Default for MetricsHistory {
    fn default() -> Self {
}

/// Broadcast payload for metrics updates via WebSocket.
#[cfg(feature = "metrics")]
#[derive(Debug, Clone, serde::Serialize)]
pub struct MetricsUpdatePayload {
    ...
}

use moltis_protocol::{ConnectParams, EventFrame};

use moltis_tools::sandbox::SandboxRouter;

use {moltis_channels::ChannelReplyTarget, moltis_sessions::session_events::SessionEventBus};

use crate::{
    auth::{CredentialStore, ResolvedAuth},
    nodes::NodeRegistry,
    pairing::{PairingState, PairingStore},
    services::GatewayServices,
};

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct TtsRuntimeOverride {
    ...
}

// ── Connected client ─────────────────────────────────────────────────────────

/// A WebSocket client currently connected to the gateway.
#[derive(Debug)]
pub struct ConnectedClient {
    ...
}

impl ConnectedClient {
    pub fn role(&self) -> &str {

    pub fn scopes(&self) -> Vec<&str> {
    ...
}

    pub fn has_scope(&self, scope: &str) -> bool {
    ...
}

    /// Check whether this client is subscribed to the given event.
    /// `None` subscriptions = wildcard (receive everything).
    pub fn is_subscribed_to(&self, event: &str) -> bool {
    ...
}

    /// Check whether this client has joined the given channel.
    pub fn is_in_channel(&self, channel: &str) -> bool {
    ...
}

    /// Send a serialized JSON frame to this client.
    ///
    /// Uses `try_send` to avoid blocking; drops the frame if the client's
    /// outbound buffer is full (slow consumer protection).
    pub fn send(&self, frame: &str) -> bool {
    ...
}

    /// Touch the activity timestamp.
    pub fn touch(&mut self) {
    ...
}
}

// ── Pending node invoke ─────────────────────────────────────────────────────

/// A pending RPC invocation waiting for a node to respond.
pub struct PendingInvoke {
    ...
}

// ── Pending client request (v4 bidir RPC) ───────────────────────────────────

/// A server-initiated RPC request waiting for a client response.
pub struct PendingClientRequest {
    ...
}

// ── Discovered hook info ─────────────────────────────────────────────────────

/// Metadata about a discovered hook, exposed to the web UI.
#[derive(Debug, Clone, serde::Serialize)]
pub struct DiscoveredHookInfo {
    ...
}

// ── Mutable runtime state ────────────────────────────────────────────────────

/// All mutable runtime state, protected by the single `RwLock` on `GatewayState`.
pub struct GatewayInner {
    ...
}

impl GatewayInner {
    fn new(hook_registry: Option<Arc<moltis_common::hooks::HookRegistry>>) -> Self {
            #[cfg(feature = "metrics")]
            #[cfg(feature = "push-notifications")]

    /// Insert a client, returning the new client count.
    pub fn register_client(&mut self, client: ConnectedClient) -> usize {
    ...
}

    /// Remove a client by conn_id. Returns the removed client and the new count.
    pub fn remove_client(&mut self, conn_id: &str) -> (Option<ConnectedClient>, usize) {
    ...
}
}

// ── Gateway state ────────────────────────────────────────────────────────────

/// Shared gateway runtime state, wrapped in `Arc` for use across async tasks.
///
/// Immutable fields and atomics live directly on this struct (no lock needed).
/// All mutable runtime state is consolidated in [`GatewayInner`] behind a
/// single `RwLock`.
pub struct GatewayState {
    ...
}

impl GatewayState {
    pub fn new(auth: ResolvedAuth, services: GatewayServices) -> Arc<Self> {
            #[cfg(feature = "metrics")]
            #[cfg(feature = "metrics")]
            #[cfg(feature = "vault")]

    #[allow(clippy::too_many_arguments)]
    pub fn with_options(
        auth: ResolvedAuth,
        services: GatewayServices,
        sandbox_router: Option<Arc<SandboxRouter>>,
        credential_store: Option<Arc<CredentialStore>>,
        pairing_store: Option<Arc<PairingStore>>,
        localhost_only: bool,
        behind_proxy: bool,
        tls_active: bool,
        hook_registry: Option<Arc<moltis_common::hooks::HookRegistry>>,
        memory_manager: Option<Arc<moltis_memory::manager::MemoryManager>>,
        port: u16,
        ws_request_logs: bool,
        deploy_platform: Option<String>,
        session_event_bus: Option<SessionEventBus>,
        #[cfg(feature = "metrics")] metrics_handle: Option<MetricsHandle>,
        #[cfg(feature = "metrics")] metrics_store: Option<Arc<dyn MetricsStore>>,
        #[cfg(feature = "vault")] vault: Option<Arc<moltis_vault::Vault>>,
    ) -> Arc<Self> {
    ...
}

    /// Process uptime in milliseconds since this gateway state was created.
    pub fn uptime_ms(&self) -> u64 {
    ...
}

    /// Set a late-bound chat service (for circular init).
    pub async fn set_chat(&self, chat: Arc<dyn crate::services::ChatService>) {
    ...
}

    /// Set the push notification service (late-bound initialization).
    #[cfg(feature = "push-notifications")]
    pub async fn set_push_service(&self, service: Arc<crate::push::PushService>) {
    ...
}

    /// Get the push notification service if configured.
    #[cfg(feature = "push-notifications")]
    pub async fn get_push_service(&self) -> Option<Arc<crate::push::PushService>> {
    ...
}

    /// Return the next sequential index for TTS phrase round-robin picking.
    pub fn next_tts_phrase_index(&self, len: usize) -> usize {
    ...
}

    /// Get the active chat service (override or default).
    pub async fn chat(&self) -> Arc<dyn crate::services::ChatService> {
    ...
}

    pub fn next_seq(&self) -> u64 {
    ...
}

    #[cfg(feature = "graphql")]
    pub fn is_graphql_enabled(&self) -> bool {
    ...
}

    #[cfg(feature = "graphql")]
    pub fn set_graphql_enabled(&self, enabled: bool) {
    ...
}

    /// Register a new client connection.
    pub async fn register_client(&self, client: ConnectedClient) {
    ...
}

    /// Remove a client by conn_id. Returns the removed client if found.
    pub async fn remove_client(&self, conn_id: &str) -> Option<ConnectedClient> {
    ...
}

    /// Number of connected clients.
    pub async fn client_count(&self) -> usize {
    ...
}

    /// Push a reply target for a session (used when a channel message triggers chat.send).
    pub async fn push_channel_reply(&self, session_key: &str, target: ChannelReplyTarget) {
    ...
}

    /// Drain all pending reply targets for a session.
    pub async fn drain_channel_replies(&self, session_key: &str) -> Vec<ChannelReplyTarget> {
    ...
}

    /// Get a copy of pending reply targets without removing them.
    pub async fn peek_channel_replies(&self, session_key: &str) -> Vec<ChannelReplyTarget> {
    ...
}

    /// Record a run error (for send_sync to retrieve).
    /// Capped at 1000 entries; stale entries (>5 min) are evicted opportunistically.
    pub async fn set_run_error(&self, run_id: &str, error: String) {
    ...
}

    /// Take (and remove) the last error for a run_id.
    pub async fn last_run_error(&self, run_id: &str) -> Option<String> {
    ...
}

    /// Append a status line (e.g. tool use, model selection) to the channel
    /// status log for a session. These are drained and appended as a logbook
    /// when the final response is delivered. Capped at 100 entries per session
    /// to prevent unbounded growth.
    pub async fn push_channel_status_log(&self, session_key: &str, message: String) {
    ...
}

    /// Drain all buffered status log entries for a session.
    pub async fn drain_channel_status_log(&self, session_key: &str) -> Vec<String> {
    ...
}

    /// Enable or disable /sh command mode for a channel session.
    pub async fn set_channel_command_mode(&self, session_key: &str, enabled: bool) {
    ...
}

    /// Check whether /sh command mode is enabled for a channel session.
    pub async fn is_channel_command_mode_enabled(&self, session_key: &str) -> bool {
    ...
}

    /// Mark a hostname as needing passkey refresh.
    pub async fn add_passkey_host_update_pending(&self, host: &str) {
    ...
}

    /// Clear the passkey-refresh marker for a hostname.
    pub async fn clear_passkey_host_update_pending(&self, host: &str) {
    ...
}

    /// Clear all pending passkey host update markers.
    pub async fn clear_all_passkey_host_update_pending(&self) {
    ...
}

    /// Return sorted hostnames that currently require a passkey refresh.
    pub async fn passkey_host_update_pending(&self) -> Vec<String> {
    ...
}

    /// Send an RPC request to a connected client and await its response (v4 bidirectional RPC).
    pub async fn send_client_request(
        &self,
        conn_id: &str,
        method: &str,
        params: serde_json::Value,
        timeout: std::time::Duration,
    ) -> Result<serde_json::Value, moltis_protocol::ErrorShape> {
    ...
}

    /// Close a client: remove from registry and unregister from nodes.
    pub async fn close_client(&self, conn_id: &str) -> Option<ConnectedClient> {
    ...
}

    /// Disconnect all WebSocket clients: send an `auth.credentials_changed`
    /// event so browsers can redirect to login, then drain every connection.
    pub async fn disconnect_all_clients(&self, reason: &str) {
    ...
}
}

#[cfg(test)]
mod tests {

    fn test_state() -> Arc<GatewayState> {
    ...
}

    fn mock_client(conn_id: &str) -> (ConnectedClient, mpsc::Receiver<String>) {
    ...
}

    #[tokio::test]
    async fn disconnect_all_clients_drains_state_and_notifies() {
    ...
}

    #[tokio::test]
    async fn disconnect_all_clients_is_noop_when_empty() {
    ...
}

    // ── Subscription tests ──────────────────────────────────────────────

    #[test]
    fn is_subscribed_to_none_is_wildcard() {
    ...
}

    #[test]
    fn is_subscribed_to_empty_set_blocks_all() {
    ...
}

    #[test]
    fn is_subscribed_to_specific_events() {
    ...
}

    #[test]
    fn is_subscribed_to_wildcard_in_set() {
    ...
}

    // ── Channel tests ───────────────────────────────────────────────────

    #[test]
    fn is_in_channel_empty() {
    ...
}

    #[test]
    fn is_in_channel_after_join() {
    ...
}

    // ── Broadcast subscription filtering ────────────────────────────────

    #[tokio::test]
    async fn broadcast_skips_unsubscribed_clients() {
    ...
}

    #[tokio::test]
    async fn broadcast_channel_filter_skips_non_members() {
    ...
}
}
