//! SQLite-backed cron store using sqlx.

use {
    async_trait::async_trait,
    sqlx::{Row, SqlitePool, sqlite::SqlitePoolOptions},
};

use crate::{
    Error, Result,
    store::CronStore,
    types::{CronJob, CronRunRecord},
};

/// SQLite-backed persistence for cron jobs and run history.
pub struct SqliteStore {
    ...
}

impl SqliteStore {
    /// Create a new store with its own connection pool and run migrations.
    ///
    /// Use this for standalone cron databases. For shared pools (e.g., moltis.db),
    /// use [`SqliteStore::with_pool`] after calling [`crate::run_migrations`].
    pub async fn new(database_url: &str) -> Result<Self> {

    /// Create a store using an existing pool (migrations must already be run).
    ///
    /// Call [`crate::run_migrations`] before using this constructor.
    pub fn with_pool(pool: SqlitePool) -> Self {
    ...
}
}

#[async_trait]
impl CronStore for SqliteStore {
    async fn load_jobs(&self) -> Result<Vec<CronJob>> {

    async fn save_job(&self, job: &CronJob) -> Result<()> {
    ...
}

    async fn delete_job(&self, id: &str) -> Result<()> {
    ...
}

    async fn update_job(&self, job: &CronJob) -> Result<()> {
    ...
}

    async fn append_run(&self, job_id: &str, run: &CronRunRecord) -> Result<()> {
    ...
}

    async fn get_runs(&self, job_id: &str, limit: usize) -> Result<Vec<CronRunRecord>> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
