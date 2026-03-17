//! Core hook types shared across crates.
//!
//! These types define the hook event system. The full registry and shell handler
//! live in `moltis-plugins`; this module provides the trait and types needed by
//! crates like `moltis-agents` that cannot depend on plugins.

use std::{
    collections::HashMap,
    fmt,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use {
    crate::error::Result,
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    serde_json::Value,
    tracing::{debug, info, warn},
};

// ── HookEvent ───────────────────────────────────────────────────────────────

/// Lifecycle events that hooks can subscribe to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum HookEvent {
    ...
}

impl fmt::Display for HookEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
}

impl HookEvent {
    /// All variants, for iteration.
    pub const ALL: &'static [HookEvent] = &[
        Self::BeforeAgentStart,
        Self::AgentEnd,
        Self::BeforeLLMCall,
        Self::AfterLLMCall,
        Self::BeforeCompaction,
        Self::AfterCompaction,
        Self::MessageReceived,
        Self::MessageSending,
        Self::MessageSent,
        Self::BeforeToolCall,
        Self::AfterToolCall,
        Self::ToolResultPersist,
        Self::SessionStart,
        Self::SessionEnd,
        Self::GatewayStart,
        Self::GatewayStop,
        Self::Command,
    ];

    /// Returns true if this event is read-only and handlers can run in parallel.
    pub fn is_read_only(&self) -> bool {
}

// ── HookPayload ─────────────────────────────────────────────────────────────

/// Typed payload carried with each hook event.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event")]
pub enum HookPayload {
    ...
}

impl HookPayload {
    /// Returns the [`HookEvent`] variant that matches this payload.
    pub fn event(&self) -> HookEvent {
}

// ── HookAction ──────────────────────────────────────────────────────────────

/// The outcome a hook handler returns.
#[derive(Debug, Default)]
pub enum HookAction {
    ...
}

// ── HookHandler trait ───────────────────────────────────────────────────────

/// Trait implemented by both native and shell hook handlers.
#[async_trait]
pub trait HookHandler: Send + Sync {
    /// A human-readable name for this handler.
    fn name(&self) -> &str;

    /// Which events this handler subscribes to.
    fn events(&self) -> &[HookEvent];

    /// Priority for ordering. Higher values run first. Default is 0.
    fn priority(&self) -> i32 {
    ...
}

    /// Handle the event, returning an action that may modify or block the flow.
    async fn handle(&self, event: HookEvent, payload: &HookPayload) -> Result<HookAction>;

    /// Synchronous handle for hot-path use (e.g. `ToolResultPersist`).
    /// Default implementation blocks on the async `handle`.
    fn handle_sync(&self, event: HookEvent, payload: &HookPayload) -> Result<HookAction> {
    ...
}
}

// ── HookStats ───────────────────────────────────────────────────────────────

/// Per-handler health statistics for circuit breaker logic.
pub struct HookStats {
    ...
}

impl HookStats {
    pub fn new() -> Self {

    pub fn record_success(&self, latency: Duration) {
    ...
}

    pub fn record_failure(&self, latency: Duration) {
    ...
}

    pub fn avg_latency(&self) -> Duration {
    ...
}
}

impl Default for HookStats {
    fn default() -> Self {
}

// ── Handler entry (with stats) ──────────────────────────────────────────────

struct HandlerEntry {
    ...
}

// ── HookRegistry ────────────────────────────────────────────────────────────

/// Manages registered hook handlers and dispatches events to them.
pub struct HookRegistry {
    ...
}

impl HookRegistry {
    pub fn new() -> Self {

    /// Set circuit breaker parameters.
    pub fn with_circuit_breaker(mut self, threshold: u64, cooldown: Duration) -> Self {
    ...
}

    /// Enable dry-run mode.
    pub fn with_dry_run(mut self, dry_run: bool) -> Self {
    ...
}

    /// Register a handler for all events it subscribes to.
    /// Handlers are sorted by priority (descending) within each event.
    pub fn register(&mut self, handler: Arc<dyn HookHandler>) {
    ...
}

    /// Returns true if any handlers are registered for the given event.
    pub fn has_handlers(&self, event: HookEvent) -> bool {
    ...
}

    /// Get stats for a named handler. Returns None if not found.
    pub fn handler_stats(&self, name: &str) -> Option<Arc<HookStats>> {
    ...
}

    /// List all registered handler names (deduplicated).
    pub fn handler_names(&self) -> Vec<String> {
    ...
}

    /// Check if a handler is circuit-broken and potentially re-enable it.
    fn check_circuit_breaker(&self, entry: &HandlerEntry) -> bool {
    ...
}

    /// Dispatch an event to all registered handlers.
    ///
    /// Read-only events dispatch handlers in parallel (results are collected
    /// but Block/Modify are ignored since the event is informational).
    /// Modifying events dispatch sequentially:
    /// - Returns the first [`HookAction::Block`] encountered (short-circuits).
    /// - Returns the last [`HookAction::ModifyPayload`] if any.
    /// - Otherwise returns [`HookAction::Continue`].
    pub async fn dispatch(&self, payload: &HookPayload) -> Result<HookAction> {
    ...
}

    /// Dispatch handlers in parallel. Block/Modify actions are logged but
    /// don't affect the event flow (read-only events are informational).
    async fn dispatch_parallel(
        &self,
        event: HookEvent,
        payload: &HookPayload,
        handlers: &[HandlerEntry],
    ) -> Result<HookAction> {
    ...
}

    /// Dispatch handlers sequentially (for modifying events).
    async fn dispatch_sequential(
        &self,
        event: HookEvent,
        payload: &HookPayload,
        handlers: &[HandlerEntry],
    ) -> Result<HookAction> {
    ...
}

    /// Synchronous dispatch for hot-path events like `ToolResultPersist`.
    pub fn dispatch_sync(&self, payload: &HookPayload) -> Result<HookAction> {
    ...
}
}

impl Default for HookRegistry {
    fn default() -> Self {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[async_trait]
    impl HookHandler for PriorityHandler {
        fn name(&self) -> &str {

        fn events(&self) -> &[HookEvent] {
    ...
}

        fn priority(&self) -> i32 {
    ...
}

        async fn handle(&self, _event: HookEvent, _payload: &HookPayload) -> Result<HookAction> {
    ...
}
    }

    struct BlockingPriorityHandler {
    ...
}

    #[async_trait]
    impl HookHandler for BlockingPriorityHandler {
        fn name(&self) -> &str {

        fn events(&self) -> &[HookEvent] {
    ...
}

        fn priority(&self) -> i32 {
    ...
}

        async fn handle(&self, _event: HookEvent, _payload: &HookPayload) -> Result<HookAction> {
    ...
}
    }

    fn modifying_payload() -> HookPayload {
    ...
}

    fn read_only_payload() -> HookPayload {
    ...
}

    #[test]
    fn priority_ordering() {
    ...
}

    #[tokio::test]
    async fn higher_priority_block_wins() {
    ...
}

    #[tokio::test]
    async fn read_only_events_ignore_block() {
    ...
}

    #[tokio::test]
    async fn circuit_breaker_trips_after_failures() {
    ...
}

    #[tokio::test]
    async fn dry_run_does_not_block() {
    ...
}

    #[test]
    fn command_event_and_payload() {
    ...
}

    #[test]
    fn hook_stats_tracking() {
    ...
}

    #[test]
    fn read_only_classification() {
    ...
}

    #[test]
    fn before_llm_call_payload_event() {
    ...
}

    #[test]
    fn after_llm_call_payload_event() {
    ...
}

    #[test]
    fn all_events_array_includes_llm_hooks() {
    ...
}

    #[test]
    fn llm_hook_payloads_serialize_round_trip() {
    ...
}
}
