//! Metrics history storage.
//!
//! This module provides a trait-based abstraction for persisting metrics history
//! to enable historical charts that survive restarts.

use {
    crate::Result,
    serde::{Deserialize, Serialize},
    sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous},
    std::{collections::HashMap, path::Path, str::FromStr, time::Duration},
};

/// Per-provider token metrics for a single time point.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderTokens {
    ...
}

/// A historical metrics data point for time-series charts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsHistoryPoint {
    ...
}

/// Trait for metrics history storage backends.
///
/// Implementations can store metrics history in SQLite, TimescaleDB,
/// or any other time-series database.
#[async_trait::async_trait]
pub trait MetricsStore: Send + Sync {
    /// Save a new metrics data point.
    async fn save_point(&self, point: &MetricsHistoryPoint) -> Result<()>;

    /// Load metrics history since a given timestamp (millis).
    ///
    /// Returns points ordered by timestamp ascending.
    /// If `since` is 0, returns all points up to `limit`.
    async fn load_history(&self, since: u64, limit: usize) -> Result<Vec<MetricsHistoryPoint>>;

    /// Delete metrics older than the given timestamp (millis).
    ///
    /// Returns the number of deleted rows.
    async fn cleanup_before(&self, before: u64) -> Result<u64>;

    /// Get the most recent data point, if any.
    async fn latest_point(&self) -> Result<Option<MetricsHistoryPoint>>;
}

/// SQLite-based metrics store.
///
/// Stores metrics history in a SQLite database file.
pub struct SqliteMetricsStore {
    ...
}

/// Metrics persistence is low-throughput (one write every 30 seconds), so a
/// single dedicated SQLite connection avoids cross-connection lock contention.
const METRICS_POOL_MAX_CONNECTIONS: u32 = 1;
/// Allow lock waits long enough for transient contention while still surfacing
/// genuinely slow queries through SQLx slow-statement logs.
const METRICS_BUSY_TIMEOUT: Duration = Duration::from_secs(30);

impl SqliteMetricsStore {
    /// Create a new SQLite metrics store.
    ///
    /// Opens or creates the database at the given path.
    pub async fn new(path: &Path) -> Result<Self> {

    /// Create an in-memory SQLite metrics store (for testing).
    #[allow(clippy::unwrap_used, clippy::expect_used)]
    #[cfg(test)]
    pub async fn in_memory() -> Result<Self> {
    ...
}

    async fn migrate(pool: &sqlx::SqlitePool) -> Result<()> {
    ...
}
}

#[async_trait::async_trait]
impl MetricsStore for SqliteMetricsStore {
    async fn save_point(&self, point: &MetricsHistoryPoint) -> Result<()> {

    async fn load_history(&self, since: u64, limit: usize) -> Result<Vec<MetricsHistoryPoint>> {
    ...
}

    async fn cleanup_before(&self, before: u64) -> Result<u64> {
    ...
}

    async fn latest_point(&self) -> Result<Option<MetricsHistoryPoint>> {
    ...
}
}

/// Internal row type for SQLite queries.
#[derive(sqlx::FromRow)]
struct MetricsRow {
    ...
}

impl From<MetricsRow> for MetricsHistoryPoint {
    fn from(row: MetricsRow) -> Self {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_save_and_load() {
    ...
}

    #[tokio::test]
    async fn test_save_and_load_with_provider() {
    ...
}

    #[tokio::test]
    async fn test_load_since() {
    ...
}

    #[tokio::test]
    async fn test_cleanup() {
    ...
}

    #[tokio::test]
    async fn test_latest_point() {
    ...
}
}
