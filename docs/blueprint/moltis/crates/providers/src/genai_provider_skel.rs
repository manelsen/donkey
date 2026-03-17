use std::pin::Pin;

use {async_trait::async_trait, futures::StreamExt, tokio_stream::Stream};

use moltis_agents::model::{
    ChatMessage, CompletionResponse, LlmProvider, StreamEvent, Usage, UserContent,
};

/// Provider backed by the `genai` crate (supports Anthropic, OpenAI, Gemini,
/// Groq, Ollama, xAI, DeepSeek, Cohere, and more via a single client).
pub struct GenaiProvider {
    ...
}

impl GenaiProvider {
    /// Create a new `GenaiProvider` with an explicit API key passed via
    /// `AuthResolver`, avoiding the need to set environment variables.
    pub fn new(model: String, provider_name: String, api_key: secrecy::Secret<String>) -> Self {
}

fn genai_usage_to_usage(u: &genai::chat::Usage) -> Usage {
    ...
}

fn build_genai_messages(messages: &[ChatMessage]) -> Vec<genai::chat::ChatMessage> {
    ...
}

#[async_trait]
impl LlmProvider for GenaiProvider {
    fn name(&self) -> &str {

    fn id(&self) -> &str {
    ...
}

    async fn complete(
        &self,
        messages: &[ChatMessage],
        _tools: &[serde_json::Value],
    ) -> anyhow::Result<CompletionResponse> {
    ...
}

    fn stream(
        &self,
        messages: Vec<ChatMessage>,
    ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
}
