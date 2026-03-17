//! Live cron service implementation wiring the cron crate into gateway services.

use std::sync::Arc;

use {async_trait::async_trait, serde_json::Value, tracing::error};

use moltis_cron::{
    service::CronService,
    types::{CronJobCreate, CronJobPatch},
};

use crate::services::{CronService as CronServiceTrait, ServiceError, ServiceResult};

/// Gateway-facing cron service backed by the real [`moltis_cron::service::CronService`].
pub struct LiveCronService {
    ...
}

impl LiveCronService {
    pub fn new(inner: Arc<CronService>) -> Self {

    pub fn inner(&self) -> &Arc<CronService> {
    ...
}
}

#[async_trait]
impl CronServiceTrait for LiveCronService {
    async fn list(&self) -> ServiceResult {

    async fn status(&self) -> ServiceResult {
    ...
}

    async fn add(&self, params: Value) -> ServiceResult {
    ...
}

    async fn update(&self, params: Value) -> ServiceResult {
    ...
}

    async fn remove(&self, params: Value) -> ServiceResult {
    ...
}

    async fn run(&self, params: Value) -> ServiceResult {
    ...
}

    async fn runs(&self, params: Value) -> ServiceResult {
    ...
}
}
