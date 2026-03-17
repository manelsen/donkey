/// Hybrid search: combine vector similarity and keyword/FTS results.
use std::collections::HashMap;

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram, labels, memory as mem_metrics};
use tracing::instrument;

use crate::{
    config::{CitationMode, MergeStrategy},
    embeddings::EmbeddingProvider,
    store::MemoryStore,
};

/// A search result with metadata.
#[derive(Debug, Clone)]
pub struct SearchResult {
    ...
}

impl SearchResult {
    /// Format the result text with a citation appended.
    /// Format: ` {
    pub fn text_with_citation(&self) -> String {
    ...
}

    /// Determine whether to include citations based on mode and result set.
    pub fn should_include_citations(results: &[SearchResult], mode: CitationMode) -> bool {
    ...
}
}

/// Perform hybrid search: embed the query, run vector + keyword search, merge with weights.
#[instrument(skip(store, embedder), fields(query_len = query.len(), limit))]
pub async fn hybrid_search(
    store: &dyn MemoryStore,
    embedder: &dyn EmbeddingProvider,
    query: &str,
    limit: usize,
    vector_weight: f32,
    keyword_weight: f32,
    merge_strategy: MergeStrategy,
) -> anyhow::Result<Vec<SearchResult>> {
    ...
}

/// Keyword-only search when no embedding provider is available.
#[instrument(skip(store), fields(query_len = query.len(), limit))]
pub async fn keyword_only_search(
    store: &dyn MemoryStore,
    query: &str,
    limit: usize,
) -> anyhow::Result<Vec<SearchResult>> {
    ...
}

/// Merge vector and keyword results with weighted scores. Deduplicates by chunk_id.
fn merge_results(
    vector: &[SearchResult],
    keyword: &[SearchResult],
    vector_weight: f32,
    keyword_weight: f32,
) -> Vec<SearchResult> {
    ...
}

/// Merge results using Reciprocal Rank Fusion (RRF).
///
/// RRF is rank-based and score-magnitude-agnostic, avoiding the sensitivity
/// to differing score scales between vector cosine similarity and FTS5 ranks.
///
/// Formula per result: `score = Σ weight / (rrf_k + rank + 1)`
fn merge_results_rrf(
    vector: &[SearchResult],
    keyword: &[SearchResult],
    vector_weight: f32,
    keyword_weight: f32,
    limit: usize,
) -> Vec<SearchResult> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn make_result_with_path(id: &str, path: &str, text: &str) -> SearchResult {
    ...
}

    #[test]
    fn test_merge_results_deduplication() {
    ...
}

    #[test]
    fn test_merge_empty() {
    ...
}

    #[test]
    fn test_text_with_citation() {
    ...
}

    #[test]
    fn test_text_with_citation_trims_whitespace() {
    ...
}

    #[test]
    fn test_should_include_citations_on() {
    ...
}

    #[test]
    fn test_should_include_citations_off() {
    ...
}

    #[test]
    fn test_should_include_citations_auto_single_file() {
    ...
}

    #[test]
    fn test_should_include_citations_auto_multiple_files() {
    ...
}

    #[test]
    fn test_should_include_citations_auto_empty() {
    ...
}

    #[test]
    fn test_merge_rrf_deduplication() {
    ...
}

    #[test]
    fn test_merge_rrf_empty() {
    ...
}

    #[test]
    fn test_merge_rrf_single_source() {
    ...
}

    #[test]
    fn test_rrf_vs_linear_produce_different_rankings() {
    ...
}

    #[test]
    fn test_merge_strategy_from_str() {
    ...
}

    #[test]
    fn test_citation_mode_from_str() {
    ...
}
}
