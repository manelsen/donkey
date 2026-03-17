use std::sync::Arc;

use {async_trait::async_trait, serde_json::Value, tracing::warn};

use moltis_projects::{
    ProjectStore,
    complete::complete_path,
    context::load_context_files,
    detect::{auto_detect, default_scan_dirs},
};

use crate::services::{ProjectService, ServiceError, ServiceResult};

pub struct LiveProjectService {
    ...
}

impl LiveProjectService {
    pub fn new(store: Arc<dyn ProjectStore>) -> Self {
}

#[async_trait]
impl ProjectService for LiveProjectService {
    async fn list(&self) -> ServiceResult {

    async fn get(&self, params: Value) -> ServiceResult {
    ...
}

    async fn upsert(&self, params: Value) -> ServiceResult {
    ...
}

    async fn delete(&self, params: Value) -> ServiceResult {
    ...
}

    async fn detect(&self, params: Value) -> ServiceResult {
    ...
}

    async fn complete_path(&self, params: Value) -> ServiceResult {
    ...
}

    async fn context(&self, params: Value) -> ServiceResult {
    ...
}
}
