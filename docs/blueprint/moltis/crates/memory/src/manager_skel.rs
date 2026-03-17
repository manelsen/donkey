/// Memory manager: orchestrates file sync, chunking, embedding, and search.
use std::path::Path;

use {
    async_trait::async_trait,
    sha2::{Digest, Sha256},
    tracing::{debug, info, warn},
    walkdir::WalkDir,
};

use moltis_agents::memory_writer::{MemoryWriteResult, MemoryWriter};

use crate::{
    chunker::chunk_content,
    config::MemoryConfig,
    embeddings::EmbeddingProvider,
    schema::{ChunkRow, FileRow},
    search::{self, SearchResult},
    store::{CacheEntry, MemoryStore},
    writer::validate_memory_path,
};

pub struct MemoryManager {
    ...
}

/// Status info about the memory system.
#[derive(Debug, Clone)]
pub struct MemoryStatus {
    ...
}

impl MemoryStatus {
    /// Human-readable database size (e.g. "12.3 MB").
    pub fn db_size_display(&self) -> String {
}

fn format_bytes(bytes: u64) -> String {
    ...
}

impl MemoryManager {
    /// Create a memory manager with an embedding provider for hybrid (vector + keyword) search.
    pub fn new(
        config: MemoryConfig,
        store: Box<dyn MemoryStore>,
        embedder: Box<dyn EmbeddingProvider>,
    ) -> Self {

    /// Create a memory manager without embeddings. Keyword (FTS) search only.
    pub fn keyword_only(config: MemoryConfig, store: Box<dyn MemoryStore>) -> Self {
    ...
}

    /// Whether this manager has an embedding provider for vector search.
    pub fn has_embeddings(&self) -> bool {
    ...
}

    /// Get the citation mode for this manager.
    pub fn citation_mode(&self) -> crate::config::CitationMode {
    ...
}

    /// Whether LLM reranking is enabled.
    pub fn llm_reranking_enabled(&self) -> bool {
    ...
}

    /// Synchronize: walk configured directories, detect changed files, re-chunk and re-embed.
    pub async fn sync(&self) -> anyhow::Result<SyncReport> {
    ...
}

    /// Sync a single file by path. Returns true if it was updated.
    pub async fn sync_path(&self, path: &Path) -> anyhow::Result<bool> {
    ...
}

    /// Sync a single file. Returns true if it was updated. Accumulates cache stats in `report`.
    async fn sync_file(
        &self,
        path: &Path,
        path_str: &str,
        report: &mut SyncReport,
    ) -> anyhow::Result<bool> {
    ...
}

    /// Search memory. Uses hybrid (vector + keyword) when embeddings are available,
    /// falls back to keyword-only search otherwise.
    #[tracing::instrument(skip(self), fields(query_len = query.len(), limit))]
    pub async fn search(&self, query: &str, limit: usize) -> anyhow::Result<Vec<SearchResult>> {
    ...
}

    /// Get a specific chunk by ID.
    pub async fn get_chunk(&self, id: &str) -> anyhow::Result<Option<ChunkRow>> {
    ...
}

    /// Get status information about the memory system.
    pub async fn status(&self) -> anyhow::Result<MemoryStatus> {
    ...
}
}

/// Maximum content size per write (50 KB).
const MAX_CONTENT_BYTES: usize = 50 * 1024;

#[async_trait]
impl MemoryWriter for MemoryManager {
    async fn write_memory(
        &self,
        file: &str,
        content: &str,
        append: bool,
    ) -> anyhow::Result<MemoryWriteResult> {
}

/// Sync report.
#[derive(Debug, Default)]
pub struct SyncReport {
    ...
}

/// Maximum number of embedding cache rows before LRU eviction kicks in.
const CACHE_MAX_ROWS: usize = 50_000;

fn sha256_hex(data: &str) -> String {
    ...
}

fn chrono_now() -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    /// Mock embedding provider that produces deterministic vectors from content.
    ///
    /// Uses a simple bag-of-keywords approach: each of 8 dimensions corresponds to a
    /// keyword. If the text contains that keyword the dimension is 1.0, otherwise 0.0.
    /// This lets vector search distinguish topics in tests.
    struct MockEmbedder;

    const KEYWORDS: [&str; 8] = [
        "rust", "python", "database", "memory", "search", "network", "cooking", "music",
    ];

    fn keyword_embedding(text: &str) -> Vec<f32> {
    ...
}

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

    async fn setup() -> (MemoryManager, TempDir) {
    ...
}

    #[tokio::test]
    async fn test_sync_and_search() {
    ...
}

    #[tokio::test]
    async fn test_sync_detects_changes() {
    ...
}

    #[tokio::test]
    async fn test_sync_removes_deleted_files() {
    ...
}

    /// End-to-end: sync markdown files, then search and verify the returned text
    /// matches what was written.
    #[tokio::test]
    async fn test_search_returns_synced_content() {
    ...
}

    /// Keyword (FTS) search works through the manager after sync.
    #[tokio::test]
    async fn test_keyword_search_through_manager() {
    ...
}

    /// Multiple files with distinct topics: searching for one topic should rank that
    /// file's chunks higher than unrelated files.
    #[tokio::test]
    async fn test_multi_file_topic_separation() {
    ...
}

    /// Sync many files and verify search still completes (basic scale sanity check).
    #[tokio::test]
    async fn test_scale_many_files() {
    ...
}

    /// Keyword-only mode: sync and search without any embedding provider.
    #[tokio::test]
    async fn test_keyword_only_mode() {
    ...
}

    /// Mock embedder that counts how many texts it has been asked to embed.
    struct CountingEmbedder {
    ...
}

    impl CountingEmbedder {
        fn new() -> Self {

        fn count(&self) -> usize {
    ...
}
    }

    #[async_trait]
    impl EmbeddingProvider for CountingEmbedder {
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

    #[tokio::test]
    async fn test_embedding_cache_hits() {
    ...
}

    #[test]
    fn test_sha256_hex() {
    ...
}

    // --- MemoryWriter impl tests ---

    /// Create a `MemoryManager` with `data_dir` set, enabling write support.
    async fn setup_writable() -> (MemoryManager, TempDir) {

    #[tokio::test]
    async fn test_memory_writer_overwrite() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_append() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_creates_parent_dir() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_size_limit() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_rejects_path_traversal() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_rejects_absolute_paths() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_rejects_invalid_names() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_reindexes() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_returns_correct_result() {
    ...
}

    #[tokio::test]
    async fn test_memory_writer_disabled_without_data_dir() {
    ...
}
}
