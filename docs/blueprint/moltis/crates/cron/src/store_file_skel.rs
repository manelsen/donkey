//! JSON file-backed cron store with atomic writes.

use std::path::PathBuf;

use {
    async_trait::async_trait,
    tokio::{fs, io::AsyncWriteExt},
};

use crate::{
    Error, Result,
    store::CronStore,
    types::{CronJob, CronRunRecord},
};

/// File-backed store. Jobs in a single JSON file, runs as JSONL per job.
pub struct FileStore {
    ...
}

impl FileStore {
    pub fn new(jobs_path: PathBuf, runs_dir: PathBuf) -> Self {

    /// Create a store using the default `<data_dir>/cron/` layout.
    pub fn default_path() -> Result<Self> {
    ...
}

    async fn ensure_dirs(&self) -> Result<()> {
    ...
}

    /// Atomic write: write to temp, rename over target, keep `.bak`.
    async fn atomic_write_jobs(&self, jobs: &[CronJob]) -> Result<()> {
    ...
}

    fn runs_path(&self, job_id: &str) -> PathBuf {
    ...
}
}

#[async_trait]
impl CronStore for FileStore {
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
