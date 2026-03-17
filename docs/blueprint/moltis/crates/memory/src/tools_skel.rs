/// Agent tools for memory search, retrieval, and persistence.
use std::sync::Arc;

use {async_trait::async_trait, moltis_agents::tool_registry::AgentTool, serde_json::json};

use crate::manager::MemoryManager;

/// Tool: search memory with a natural language query.
pub struct MemorySearchTool {
    ...
}

impl MemorySearchTool {
    pub fn new(manager: Arc<MemoryManager>) -> Self {
}

#[async_trait]
impl AgentTool for MemorySearchTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

/// Tool: get a specific memory chunk by ID.
pub struct MemoryGetTool {
    ...
}

impl MemoryGetTool {
    pub fn new(manager: Arc<MemoryManager>) -> Self {
}

#[async_trait]
impl AgentTool for MemoryGetTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

/// Tool: save content to long-term memory files.
pub struct MemorySaveTool {
    ...
}

impl MemorySaveTool {
    pub fn new(manager: Arc<MemoryManager>) -> Self {
}

#[async_trait]
impl AgentTool for MemorySaveTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    /// Same keyword-based mock embedder used in manager tests.
    const KEYWORDS: [&str; 8] = [
        "rust", "python", "database", "memory", "search", "network", "cooking", "music",
    ];

    struct MockEmbedder;

    #[async_trait]
    impl EmbeddingProvider for MockEmbedder {
        async fn embed(&self, text: &str) -> anyhow::Result<Vec<f32>> {

        fn model_name(&self) -> &str {
    ...
}

        fn dimensions(&self) -> usize {
    ...
}

        fn provider_key(&self) -> &str {
    ...
}
    }

    /// Set up a memory manager in a temporary directory.
    ///
    /// Returns the Arc'd manager, the TempDir handle, and the data_dir path
    /// (which is `tmp.path()` — the root for MEMORY.md and memory/).
    async fn setup_manager() -> (Arc<MemoryManager>, TempDir) {
    ...
}

    #[test]
    fn test_memory_search_tool_schema() {
    ...
}

    #[test]
    fn test_memory_get_tool_schema() {
    ...
}

    /// Execute memory_search via the tool interface and verify JSON output structure.
    #[tokio::test]
    async fn test_memory_search_tool_execute() {
    ...
}

    /// Execute memory_search with missing query — should return an error.
    #[tokio::test]
    async fn test_memory_search_tool_missing_query() {
    ...
}

    /// Execute memory_get for an existing chunk.
    #[tokio::test]
    async fn test_memory_get_tool_execute() {
    ...
}

    /// Execute memory_get for a non-existent chunk — should return error JSON (not a Rust error).
    #[tokio::test]
    async fn test_memory_get_tool_not_found() {
    ...
}

    /// Execute memory_get with missing chunk_id — should return an error.
    #[tokio::test]
    async fn test_memory_get_tool_missing_param() {
    ...
}

    /// Round-trip: sync → search via tool → get via tool → verify text matches.
    #[tokio::test]
    async fn test_tools_round_trip() {
    ...
}

    // ---- MemorySaveTool tests ----

    #[test]
    fn test_memory_save_tool_schema() {
    ...
}

    /// Default append mode: two writes produce both contents in the file.
    #[tokio::test]
    async fn test_memory_save_append_default() {
    ...
}

    /// Overwrite mode: second write replaces the first.
    #[tokio::test]
    async fn test_memory_save_overwrite() {
    ...
}

    /// Custom file under memory/ subdirectory.
    #[tokio::test]
    async fn test_memory_save_custom_file() {
    ...
}

    /// Auto-creates memory/ directory if it doesn't exist.
    #[tokio::test]
    async fn test_memory_save_creates_memory_dir() {
    ...
}

    /// Re-indexes after write so content is immediately searchable.
    #[tokio::test]
    async fn test_memory_save_reindexes() {
    ...
}

    /// Path traversal attempts are rejected.
    #[tokio::test]
    async fn test_memory_save_rejects_path_traversal() {
    ...
}

    /// Absolute paths are rejected.
    #[tokio::test]
    async fn test_memory_save_rejects_absolute_paths() {
    ...
}

    /// Invalid file names are rejected.
    #[tokio::test]
    async fn test_memory_save_rejects_invalid_names() {
    ...
}

    /// Missing content parameter returns an error.
    #[tokio::test]
    async fn test_memory_save_missing_content() {
    ...
}

    /// Content exceeding the size limit is rejected.
    #[tokio::test]
    async fn test_memory_save_content_size_limit() {
    ...
}

    /// Full round-trip: save → search → get → verify text matches.
    #[tokio::test]
    async fn test_memory_save_round_trip() {
    ...
}
}
