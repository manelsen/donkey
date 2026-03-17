//! Domain approval manager for trusted-network mode.
//!
//! Manages per-session domain allow/deny decisions with a config-based
//! allowlist, session-approved domains, and an interactive approval flow.

use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::Duration,
};

use {
    async_trait::async_trait,
    tokio::sync::{RwLock, oneshot},
    tracing::{debug, instrument, warn},
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram};

use crate::{ApprovalSource, DomainDecision, DomainFilter, DomainPattern, FilterAction};

struct PendingDomainRequest {
    ...
}

/// Manages domain allow/deny decisions for trusted network mode.
///
/// Follows the same pattern as `ApprovalManager` in `approval.rs`:
/// pending requests are stored with a UUID key and resolved via oneshot channels.
pub struct DomainApprovalManager {
    ...
}

impl DomainApprovalManager {
    pub fn new(allowed_domains: &[String], timeout: Duration) -> Self {

    /// Check a domain against the config allowlist and session-approved domains.
    #[instrument(skip(self), fields(session = %session, domain = %domain))]
    pub async fn check_domain(&self, session: &str, domain: &str) -> FilterAction {
    ...
}

    /// Like [`check_domain`] but also returns the approval source when allowed.
    #[instrument(skip(self), fields(session = %session, domain = %domain))]
    pub async fn check_domain_with_source(
        &self,
        session: &str,
        domain: &str,
    ) -> (FilterAction, Option<ApprovalSource>) {
    ...
}

    /// Create a pending approval request. Returns a UUID and a receiver for the decision.
    #[instrument(skip(self), fields(session = %session, domain = %domain))]
    pub async fn create_request(
        &self,
        session: &str,
        domain: &str,
    ) -> (String, oneshot::Receiver<DomainDecision>) {
    ...
}

    /// Resolve a pending domain approval request.
    /// If approved, the domain is added to the session allowlist for future requests.
    #[instrument(skip(self), fields(id = %id, decision = ?decision))]
    pub async fn resolve(&self, id: &str, decision: DomainDecision) {
    ...
}

    /// Wait for a domain approval decision with timeout.
    #[instrument(skip(self, rx))]
    pub async fn wait_for_decision(&self, rx: oneshot::Receiver<DomainDecision>) -> DomainDecision {
    ...
}

    /// Return all pending request IDs with their domains and sessions.
    pub async fn pending_requests(&self) -> Vec<(String, String, String)> {
    ...
}

    /// Add a domain to the session allowlist without going through the approval flow.
    pub async fn add_trusted_domain(&self, session: &str, domain: &str) {
    ...
}

    /// Remove a domain from the session allowlist.
    pub async fn remove_trusted_domain(&self, session: &str, domain: &str) {
    ...
}

    /// List all trusted domains for a session (config + session-approved).
    pub async fn list_trusted_domains(&self, session: &str) -> Vec<String> {
    ...
}

    /// Access the configured timeout.
    pub fn timeout(&self) -> Duration {
    ...
}
}

#[async_trait]
impl DomainFilter for DomainApprovalManager {
    async fn check(&self, session: &str, domain: &str) -> FilterAction {
}

#[async_trait]
impl DomainFilter for Arc<DomainApprovalManager> {
    async fn check(&self, session: &str, domain: &str) -> FilterAction {
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[tokio::test]
    async fn test_empty_allowlist_allows_all_domains() {
    ...
}

    #[tokio::test]
    async fn test_check_domain_session_allowlist() {
    ...
}

    #[tokio::test]
    async fn test_create_and_resolve_approved() {
    ...
}

    #[tokio::test]
    async fn test_create_and_resolve_denied() {
    ...
}

    #[tokio::test]
    async fn test_wait_for_decision_timeout() {
    ...
}

    #[tokio::test]
    async fn test_list_trusted_domains() {
    ...
}

    #[tokio::test]
    async fn test_remove_trusted_domain() {
    ...
}

    #[tokio::test]
    async fn test_pending_requests() {
    ...
}
}
