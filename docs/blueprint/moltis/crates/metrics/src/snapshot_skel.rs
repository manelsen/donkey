//! Metrics snapshot for internal API consumption.
//!
//! This module provides a way to get metrics data as structured JSON
//! for display in the web UI, separate from the Prometheus text format.

use {
    serde::{Deserialize, Serialize},
    std::collections::HashMap,
};

/// Type of metric
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MetricType {
    ...
}

/// A single metric value with its labels
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricSnapshot {
    ...
}

/// Histogram bucket and summary data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistogramSnapshot {
    ...
}

/// A single histogram bucket
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistogramBucket {
    ...
}

/// Pre-calculated percentiles for histograms
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PercentilesSnapshot {
    ...
}

/// A complete snapshot of all metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsSnapshot {
    ...
}

/// Metrics organized by category for easier UI consumption
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MetricCategories {
    ...
}

/// Generic category metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CategoryMetrics {
    ...
}

/// LLM-specific metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LlmCategoryMetrics {
    ...
}

/// Per-provider metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderMetrics {
    ...
}

/// Per-model metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ModelMetrics {
    ...
}

/// System-level metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SystemMetrics {
    ...
}

impl MetricsSnapshot {
    /// Create a new empty snapshot
    #[must_use]
    pub fn new() -> Self {

    /// Parse Prometheus text format into a structured snapshot.
    ///
    /// This is a best-effort parser that extracts metric values from
    /// Prometheus exposition format.
    #[must_use]
    pub fn from_prometheus_text(text: &str) -> Self {
    ...
}
}

impl Default for MetricsSnapshot {
    fn default() -> Self {
}

/// Parse a single Prometheus metric line
fn parse_prometheus_line(line: &str) -> Option<MetricSnapshot> {
    ...
}