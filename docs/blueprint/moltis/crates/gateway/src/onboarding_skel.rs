//! Gateway adapter: wraps `LiveOnboardingService` to implement `OnboardingService`.

use std::{path::Path, sync::Arc};

use {async_trait::async_trait, serde_json::Value};

use crate::services::{OnboardingService, ServiceError, ServiceResult};

/// Gateway-side onboarding service backed by `moltis_onboarding::service::LiveOnboardingService`.
pub struct GatewayOnboardingService {
    ...
}

impl GatewayOnboardingService {
    pub fn new(
        inner: moltis_onboarding::service::LiveOnboardingService,
        session_metadata: Arc<moltis_sessions::metadata::SqliteSessionMetadata>,
        agent_persona_store: Arc<crate::agent_persona::AgentPersonaStore>,
        gateway_state: Arc<tokio::sync::OnceCell<Arc<crate::state::GatewayState>>>,
    ) -> Self {

    /// Create imported agents as Moltis agent personas.
    ///
    /// Skips agents that already exist or are the default ("main") agent.
    #[cfg(feature = "openclaw-import")]
    async fn create_imported_agents(
        &self,
        agents: &moltis_openclaw_import::agents::ImportedAgents,
    ) -> Result<(), String> {
    ...
}

    #[cfg(feature = "openclaw-import")]
    async fn sync_imported_sessions_to_sqlite(&self, data_dir: &Path) -> Result<(), String> {
    ...
}
}

#[async_trait]
impl OnboardingService for GatewayOnboardingService {
    async fn wizard_start(&self, params: Value) -> ServiceResult {

    async fn wizard_next(&self, params: Value) -> ServiceResult {
    ...
}

    async fn wizard_cancel(&self) -> ServiceResult {
    ...
}

    async fn wizard_status(&self) -> ServiceResult {
    ...
}

    async fn identity_get(&self) -> ServiceResult {
    ...
}

    async fn identity_update(&self, params: Value) -> ServiceResult {
    ...
}

    async fn identity_update_soul(&self, soul: Option<String>) -> ServiceResult {
    ...
}

    #[cfg(feature = "openclaw-import")]
    async fn openclaw_detect(&self) -> ServiceResult {
    ...
}

    #[cfg(not(feature = "openclaw-import"))]
    async fn openclaw_detect(&self) -> ServiceResult {
    ...
}

    #[cfg(feature = "openclaw-import")]
    async fn openclaw_scan(&self) -> ServiceResult {
    ...
}

    #[cfg(not(feature = "openclaw-import"))]
    async fn openclaw_scan(&self) -> ServiceResult {
    ...
}

    #[cfg(feature = "openclaw-import")]
    async fn openclaw_import(&self, params: Value) -> ServiceResult {
    ...
}

    #[cfg(not(feature = "openclaw-import"))]
    async fn openclaw_import(&self, _params: Value) -> ServiceResult {
    ...
}
}

fn parse_geo_location(value: &Value) -> Option<moltis_config::GeoLocation> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn parse_geo_location_rejects_invalid_payload() {
    ...
}

    #[cfg(feature = "openclaw-import")]
    #[tokio::test]
    async fn sync_imported_sessions_preserves_timestamps_and_preview() {
    ...
}
}
