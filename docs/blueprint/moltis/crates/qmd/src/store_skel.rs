//! QMD implementation of the MemoryStore trait.
//!
//! This provides a bridge between the moltis memory system and the QMD backend,
//! allowing QMD to be used as an alternative to the built-in SQLite store.

use std::sync::Arc;

use {
    async_trait::async_trait,
    moltis_memory::{
        schema::{ChunkRow, FileRow},
        search::SearchResult,
        store::{CacheEntry, MemoryStore},
    },
    tracing::warn,
};

use crate::manager::QmdManager;

/// QMD-based memory store implementation.
///
/// This store delegates search operations to QMD while providing stub
/// implementations for write operations (QMD manages its own index).
pub struct QmdStore {
    ...
}

impl QmdStore {
    /// Create a new QMD store with the given manager.
    pub fn new(manager: Arc<QmdManager>) -> Self {

    /// Include built-in memory in searches.
    pub fn with_builtin_memory(mut self, include: bool) -> Self {
    ...
}

    /// Set a fallback store for write operations and when QMD is unavailable.
    pub fn with_fallback(mut self, store: Box<dyn MemoryStore>) -> Self {
    ...
}

    /// Convert a QMD search result to a moltis SearchResult.
    fn convert_result(qmd_result: &crate::manager::QmdSearchResult) -> SearchResult {
    ...
}
}

#[async_trait]
impl MemoryStore for QmdStore {
    // ── File operations (delegated to fallback or no-op) ──

    async fn upsert_file(&self, file: &FileRow) -> anyhow::Result<()> {

    async fn get_file(&self, path: &str) -> anyhow::Result<Option<FileRow>> {
    ...
}

    async fn delete_file(&self, path: &str) -> anyhow::Result<()> {
    ...
}

    async fn list_files(&self) -> anyhow::Result<Vec<FileRow>> {
    ...
}

    // ── Chunk operations (delegated to fallback or no-op) ──

    async fn upsert_chunks(&self, chunks: &[ChunkRow]) -> anyhow::Result<()> {
    ...
}

    async fn get_chunks_for_file(&self, path: &str) -> anyhow::Result<Vec<ChunkRow>> {
    ...
}

    async fn delete_chunks_for_file(&self, path: &str) -> anyhow::Result<()> {
    ...
}

    async fn get_chunk_by_id(&self, id: &str) -> anyhow::Result<Option<ChunkRow>> {
    ...
}

    // ── Embedding cache (delegated to fallback) ──

    async fn get_cached_embedding(
        &self,
        provider: &str,
        model: &str,
        hash: &str,
    ) -> anyhow::Result<Option<Vec<f32>>> {
    ...
}

    async fn put_cached_embedding(
        &self,
        provider: &str,
        model: &str,
        provider_key: &str,
        hash: &str,
        embedding: &[f32],
    ) -> anyhow::Result<()> {
    ...
}

    async fn put_cached_embeddings_batch(&self, entries: &[CacheEntry<'_>]) -> anyhow::Result<()> {
    ...
}

    async fn count_cached_embeddings(&self) -> anyhow::Result<usize> {
    ...
}

    async fn evict_embedding_cache(&self, keep: usize) -> anyhow::Result<usize> {
    ...
}

    // ── Search operations (use QMD with optional fallback) ──

    async fn vector_search(
        &self,
        _query_embedding: &[f32],
        limit: usize,
    ) -> anyhow::Result<Vec<SearchResult>> {
    ...
}

    async fn keyword_search(&self, query: &str, limit: usize) -> anyhow::Result<Vec<SearchResult>> {
    ...
}
}

/// Extension trait for QMD-specific search operations.
impl QmdStore {
    /// Perform a hybrid search using QMD (keyword + vector + LLM reranking).
    pub async fn hybrid_search(
        &self,
        query: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<SearchResult>> {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
