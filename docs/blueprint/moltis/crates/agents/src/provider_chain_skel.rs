//! Provider failover chain with per-provider circuit breakers.
//!
//! `ProviderChain` wraps a primary `LlmProvider` with a list of fallbacks.
//! When the primary fails with a retryable error (rate limit, auth, server error),
//! it automatically tries the next provider in the chain, skipping any that have
//! their circuit breaker tripped.

use std::{
    pin::Pin,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};

use {async_trait::async_trait, tokio_stream::Stream, tracing::warn};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram, labels, llm as llm_metrics};

use crate::model::{ChatMessage, CompletionResponse, LlmProvider, StreamEvent};

/// How a provider error should be handled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderErrorKind {
    ...
}

impl ProviderErrorKind {
    /// Whether this error kind should trigger failover to the next provider.
    #[must_use]
    pub fn should_failover(self) -> bool {
}

/// Error patterns for context window overflow (reused from runner.rs).
const CONTEXT_WINDOW_PATTERNS: &[&str] = &[
    "context_length_exceeded",
    "max_tokens",
    "too many tokens",
    "request too large",
    "maximum context length",
    "context window",
    "token limit",
    "content_too_large",
    "request_too_large",
];

/// Classify an error into a `ProviderErrorKind` based on the error message.
#[must_use]
pub fn classify_error(err: &anyhow::Error) -> ProviderErrorKind {
    ...
}

// ── Circuit breaker (same pattern as embeddings_fallback.rs) ─────────────

/// Circuit breaker state for a single provider.
struct ProviderState {
    ...
}

impl ProviderState {
    fn new() -> Self {

    fn record_success(&self) {
    ...
}

    fn record_failure(&self) {
    ...
}

    /// Returns `true` when the circuit is open (provider should be skipped).
    /// Trips after 3 consecutive failures; resets after 60s cooldown.
    fn is_tripped(&self) -> bool {
    ...
}
}

/// A provider entry in the failover chain.
struct ChainEntry {
    ...
}

/// Failover chain that tries providers in order, with circuit breakers.
///
/// Implements `LlmProvider` itself so callers don't need to know about failover.
pub struct ProviderChain {
    ...
}

impl ProviderChain {
    /// Build a chain from a list of providers (primary first, then fallbacks).
    pub fn new(providers: Vec<Arc<dyn LlmProvider>>) -> Self {

    /// Build a chain with one provider (no failover). Useful as a passthrough.
    pub fn single(provider: Arc<dyn LlmProvider>) -> Self {
    ...
}

    fn primary(&self) -> &ChainEntry {
    ...
}
}

#[async_trait]
impl LlmProvider for ProviderChain {
    fn name(&self) -> &str {

    fn id(&self) -> &str {
    ...
}

    fn supports_tools(&self) -> bool {
    ...
}

    fn context_window(&self) -> u32 {
    ...
}

    async fn complete(
        &self,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
    ) -> anyhow::Result<CompletionResponse> {
    ...
}

    fn stream(
        &self,
        messages: Vec<ChatMessage>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

    fn stream_with_tools(
        &self,
        messages: Vec<ChatMessage>,
        tools: Vec<serde_json::Value>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    /// A mock provider that always succeeds.
    struct SuccessProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for SuccessProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> anyhow::Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    /// A mock provider that always fails with a configurable error message.
    struct FailingProvider {
    ...
}

    #[async_trait]
    impl LlmProvider for FailingProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> anyhow::Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn primary_succeeds_no_failover() {
    ...
}

    #[tokio::test]
    async fn failover_on_rate_limit() {
    ...
}

    #[tokio::test]
    async fn failover_on_server_error() {
    ...
}

    #[tokio::test]
    async fn failover_on_auth_error() {
    ...
}

    #[tokio::test]
    async fn no_failover_on_context_window() {
    ...
}

    #[tokio::test]
    async fn no_failover_on_invalid_request() {
    ...
}

    #[tokio::test]
    async fn all_providers_fail() {
    ...
}

    #[tokio::test]
    async fn circuit_breaker_trips_after_three_failures() {
    ...
}

    #[tokio::test]
    async fn stream_uses_first_non_tripped() {
    ...
}

    #[test]
    fn classify_rate_limit() {
    ...
}

    #[test]
    fn classify_auth() {
    ...
}

    #[test]
    fn classify_server() {
    ...
}

    #[test]
    fn classify_context_window() {
    ...
}

    #[test]
    fn classify_billing() {
    ...
}

    #[test]
    fn classify_invalid_request() {
    ...
}

    #[test]
    fn classify_unknown() {
    ...
}

    #[test]
    fn should_failover_mapping() {
    ...
}

    #[test]
    fn single_provider_chain() {
    ...
}

    // ── Regression: stream_with_tools must forward tools to the provider ──

    /// A mock provider that records whether stream_with_tools received tools.
    struct ToolTrackingProvider {
    ...
}

    impl ToolTrackingProvider {
        fn new() -> Self {

        fn received_tools_count(&self) -> usize {
    ...
}
    }

    #[async_trait]
    impl LlmProvider for ToolTrackingProvider {
        fn name(&self) -> &str {

        fn id(&self) -> &str {
    ...
}

        fn supports_tools(&self) -> bool {
    ...
}

        async fn complete(
            &self,
            _messages: &[ChatMessage],
            _tools: &[serde_json::Value],
        ) -> anyhow::Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}

        fn stream_with_tools(
            &self,
            _messages: Vec<ChatMessage>,
            tools: Vec<serde_json::Value>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    #[tokio::test]
    async fn chain_stream_with_tools_forwards_tools() {
    ...
}

    #[tokio::test]
    async fn chain_stream_with_tools_forwards_empty_tools() {
    ...
}
}
