//! In-memory store for testing.

use std::{collections::HashMap, sync::Mutex};

use async_trait::async_trait;

use crate::{
    Error, Result,
    store::CronStore,
    types::{CronJob, CronRunRecord},
};

/// In-memory store backed by `HashMap`. No persistence — for tests only.
pub struct InMemoryStore {
    ...
}

impl InMemoryStore {
    pub fn new() -> Self {
}

impl Default for InMemoryStore {
    fn default() -> Self {
}

#[async_trait]
impl CronStore for InMemoryStore {
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
