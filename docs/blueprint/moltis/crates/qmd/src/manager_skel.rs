//! QMD sidecar process manager.
//!
//! Manages communication with the QMD CLI for indexing and search operations.

use std::{collections::HashMap, path::PathBuf, process::Stdio, time::Duration};

use {
    serde::{Deserialize, Serialize},
    tokio::{process::Command, sync::RwLock, time::timeout},
    tracing::{debug, info},
};

/// Configuration for the QMD manager.
#[derive(Debug, Clone)]
pub struct QmdManagerConfig {
    ...
}

impl Default for QmdManagerConfig {
    fn default() -> Self {
}

/// A QMD collection configuration.
#[derive(Debug, Clone)]
pub struct QmdCollection {
    ...
}

/// Search mode for QMD queries.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SearchMode {
    ...
}

impl SearchMode {
    fn as_command(&self) -> &str {
}

/// A search result from QMD.
#[derive(Debug, Clone, Deserialize)]
pub struct QmdSearchResult {
    ...
}

/// Status of the QMD backend.
#[derive(Debug, Clone, Serialize)]
pub struct QmdStatus {
    ...
}

/// Manager for the QMD sidecar process.
pub struct QmdManager {
    ...
}

impl QmdManager {
    /// Create a new QMD manager with the given configuration.
    pub fn new(config: QmdManagerConfig) -> Self {

    /// Check if QMD is available on this system.
    pub async fn is_available(&self) -> bool {
    ...
}

    async fn check_qmd_available(&self) -> bool {
    ...
}

    /// Get the status of the QMD backend.
    pub async fn status(&self) -> QmdStatus {
    ...
}

    async fn get_indexed_count(&self, collection: &str) -> anyhow::Result<usize> {
    ...
}

    /// Index the given paths for a collection.
    pub async fn index(&self, collection: &str, paths: &[PathBuf]) -> anyhow::Result<()> {
    ...
}

    /// Search using the specified mode.
    pub async fn search(
        &self,
        query: &str,
        mode: SearchMode,
        collection: Option<&str>,
        limit: usize,
    ) -> anyhow::Result<Vec<QmdSearchResult>> {
    ...
}

    /// Hybrid search (combines keyword, vector, and LLM reranking).
    pub async fn hybrid_search(
        &self,
        query: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<QmdSearchResult>> {
    ...
}

    /// Fast keyword search using BM25.
    pub async fn keyword_search(
        &self,
        query: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<QmdSearchResult>> {
    ...
}

    /// Vector similarity search.
    pub async fn vector_search(
        &self,
        query: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<QmdSearchResult>> {
    ...
}
}

#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_search_mode_commands() {
    ...
}

    #[tokio::test]
    async fn test_manager_unavailable() {
    ...
}
}
