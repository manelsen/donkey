/// Silent agentic turn for pre-compaction memory flush.
///
/// Before compacting a session, runs a hidden LLM turn that reviews the conversation
/// and writes important memories to disk. The LLM's response text is discarded (not
/// shown to the user). This matches OpenClaw's approach to long-term memory creation.
use std::path::PathBuf;
use std::sync::Arc;

use {
    anyhow::Result,
    tracing::{debug, info, warn},
};

use crate::{
    memory_writer::{MemoryWriteResult, MemoryWriter},
    model::{ChatMessage, LlmProvider},
    runner::run_agent_loop,
    tool_registry::{AgentTool, ToolRegistry},
};

const MEMORY_FLUSH_SYSTEM_PROMPT: &str = r#"You are a memory management agent. Your job is to review the conversation below and save any important information to memory files using the write_file tool.

Save information that would be useful in future conversations:
- User preferences and working style
- Key decisions and their reasoning
- Project context, architecture choices, and conventions
- Important facts, names, dates, and relationships
- Recurring topics or patterns
- Technical setup details (tools, languages, frameworks)

Write to these paths:
- `MEMORY.md` — Long-term facts and preferences (append new content, don't overwrite existing)
- `memory/YYYY-MM-DD.md` — Daily session log with what was done and decided today

Format files as clean Markdown. Be concise but preserve important context.
Do NOT respond to the user. Only use the write_file tool to save memories."#;

#[must_use]
fn truncate_at_char_boundary(content: &str, max_bytes: usize) -> &str {
    ...
}

/// A thin `AgentTool` wrapper around `dyn MemoryWriter` that tracks written locations.
struct MemoryWriteFileTool {
    ...
}

impl MemoryWriteFileTool {
    fn new(writer: Arc<dyn MemoryWriter>) -> Self {

    fn take_written_paths(&self) -> Vec<PathBuf> {
    ...
}
}

#[async_trait::async_trait]
impl AgentTool for MemoryWriteFileTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> Result<serde_json::Value> {
    ...
}
}

/// Run a silent memory turn before compaction.
///
/// Gives the LLM a special system prompt asking it to save important memories
/// from the conversation using `write_file`. The LLM's response text is discarded.
///
/// Returns the list of file paths that were written.
pub async fn run_silent_memory_turn(
    provider: Arc<dyn LlmProvider>,
    conversation: &[ChatMessage],
    writer: Arc<dyn MemoryWriter>,
) -> Result<Vec<PathBuf>> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    /// Mock provider that makes one write_file call then returns.
    struct MemoryWritingProvider {
    ...
}

    #[async_trait::async_trait]
    impl LlmProvider for MemoryWritingProvider {
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
        ) -> Result<CompletionResponse> {
    ...
}

        fn stream(
            &self,
            _messages: Vec<ChatMessage>,
        ) -> Pin<Box<dyn Stream<Item = StreamEvent> + Send + '_>> {
    ...
}
    }

    /// Mock MemoryWriter that writes to a temp directory.
    struct MockMemoryWriter {
    ...
}

    #[async_trait::async_trait]
    impl MemoryWriter for MockMemoryWriter {
        async fn write_memory(
            &self,
            file: &str,
            content: &str,
            append: bool,
        ) -> Result<MemoryWriteResult> {
    }

    #[tokio::test]
    async fn test_silent_memory_turn_writes_file() {
    ...
}

    #[tokio::test]
    async fn test_silent_memory_turn_no_crash_on_empty_conversation() {
    ...
}

    #[test]
    fn truncate_at_char_boundary_handles_multibyte_boundary() {
    ...
}
}
