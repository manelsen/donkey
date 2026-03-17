/// SQLite implementation of the `MemoryStore` trait.
use async_trait::async_trait;
use sqlx::SqlitePool;

use crate::{
    schema::{ChunkRow, FileRow},
    search::SearchResult,
    store::{CacheEntry, MemoryStore},
};

/// Sanitize a user query for FTS5 `MATCH`.
///
/// FTS5 has its own query grammar where characters like `.` (column filter),
/// `*` (prefix), `"` (phrase), `+`, `-`, `(`, `)`, `NEAR`, `OR`, `AND`, `NOT`
/// have special meaning.  Passing unsanitized user input (e.g. coordinates
/// like "37.759") causes `fts5: syntax error near "."`.
///
/// Strategy: split on whitespace, strip all non-alphanumeric characters from
/// each token, wrap every token in double quotes (so FTS5 treats it as a
/// literal), then join with spaces (implicit AND).
fn sanitize_fts5_query(query: &str) -> String {
    ...
}

pub struct SqliteMemoryStore {
    ...
}

impl SqliteMemoryStore {
    pub fn new(pool: SqlitePool) -> Self {

    pub fn pool(&self) -> &SqlitePool {
    ...
}
}

/// Zero-copy cast of a little-endian f32 BLOB to `&[f32]`.
///
/// Falls back to byte-by-byte deserialization if alignment or size is wrong.
fn blob_as_f32_slice(blob: &[u8]) -> std::borrow::Cow<'_, [f32]> {
    ...
}

/// Serialize a slice of f32s to a BLOB of little-endian bytes.
fn vec_to_blob(v: &[f32]) -> Vec<u8> {
    ...
}

/// Cosine similarity between two vectors.
fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    ...
}

/// A scored result for the top-K min-heap. Ordered by score ascending so the
/// minimum score is at the top, allowing us to evict the worst candidate.
struct ScoredResult {
    ...
}

impl PartialEq for ScoredResult {
    fn eq(&self, other: &Self) -> bool {
}

impl Eq for ScoredResult {}

impl PartialOrd for ScoredResult {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
    ...
}
}

impl Ord for ScoredResult {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
}

#[async_trait]
impl MemoryStore for SqliteMemoryStore {
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

    async fn vector_search(
        &self,
        query_embedding: &[f32],
        limit: usize,
    ) -> anyhow::Result<Vec<SearchResult>> {
    ...
}

    async fn keyword_search(&self, query: &str, limit: usize) -> anyhow::Result<Vec<SearchResult>> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
