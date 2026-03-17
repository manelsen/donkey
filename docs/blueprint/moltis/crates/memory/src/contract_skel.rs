//! Contract tests for the [`MemoryStore`] trait.
//!
//! These functions validate that any `MemoryStore` implementation satisfies
//! the CRUD and search invariants required by the memory system.

#![allow(clippy::unwrap_used)]

use crate::{
    schema::{ChunkRow, FileRow},
    store::MemoryStore,
};

fn test_file(path: &str) -> FileRow {
    ...
}

fn test_chunk(id: &str, path: &str, text: &str, embedding: Option<Vec<f32>>) -> ChunkRow {
    ...
}

/// Ingest a document and search for its content — must return at least one result.
pub async fn ingest_then_search_returns_result(store: &dyn MemoryStore) -> anyhow::Result<()> {
    ...
}

/// Delete a file's chunks, then search must return nothing for that content.
pub async fn delete_removes_from_search(store: &dyn MemoryStore) -> anyhow::Result<()> {
    ...
}

/// FTS keyword search finds an exact keyword match.
pub async fn keyword_search_finds_exact_match(store: &dyn MemoryStore) -> anyhow::Result<()> {
    ...
}

/// Searching an empty store must return empty results (not error).
pub async fn empty_search_returns_empty(store: &dyn MemoryStore) -> anyhow::Result<()> {
    ...
}

#[cfg(test)]
mod tests {

    async fn test_store() -> SqliteMemoryStore {
    ...
}

    #[tokio::test]
    async fn contract_ingest_then_search() {
    ...
}

    #[tokio::test]
    async fn contract_delete_removes_from_search() {
    ...
}

    #[tokio::test]
    async fn contract_keyword_search_finds_exact_match() {
    ...
}

    #[tokio::test]
    async fn contract_empty_search_returns_empty() {
    ...
}
}
