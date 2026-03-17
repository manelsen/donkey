//! Contract tests for the [`LlmProvider`] trait.
//!
//! These functions validate that any `LlmProvider` implementation satisfies
//! the completion and streaming semantics required by the chat runtime.
//! Run against `MockLlmProvider` in provider tests.

#![allow(clippy::unwrap_used)]

use std::pin::Pin;

use {
    async_trait::async_trait,
    moltis_agents::model::{ChatMessage, CompletionResponse, LlmProvider, StreamEvent, Usage},
    tokio_stream::{Stream, StreamExt},
};

// ── Mock provider ───────────────────────────────────────────────────────────

/// A mock LLM provider that returns canned responses for contract testing.
pub struct MockLlmProvider {
    ...
}

/// Simulated error types for the mock provider.
pub enum MockError {
    ...
}

impl MockLlmProvider {
    pub fn ok() -> Self {

    pub fn with_error(error: MockError) -> Self {
    ...
}
}

#[async_trait]
impl LlmProvider for MockLlmProvider {
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

// ── Contract tests ──────────────────────────────────────────────────────────

/// A non-streaming completion must return a response with text and usage data.
pub async fn non_stream_returns_complete_response(
    provider: &dyn LlmProvider,
) -> anyhow::Result<()> {
    ...
}

/// A streaming completion must eventually emit a Done event.
pub async fn stream_emits_done_signal(provider: &dyn LlmProvider) -> anyhow::Result<()> {
    ...
}

/// A 429 rate-limit error message must contain "429" (retryable indicator).
pub async fn error_classification_maps_429_to_retryable(provider: &dyn LlmProvider) {
    ...
}

/// A 401 auth error message must contain "401" (fatal indicator).
pub async fn error_classification_maps_401_to_fatal(provider: &dyn LlmProvider) {
    ...
}

#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn contract_stream_emits_done_signal() {
    ...
}

    #[tokio::test]
    async fn contract_error_classification_429() {
    ...
}

    #[tokio::test]
    async fn contract_error_classification_401() {
    ...
}
}
