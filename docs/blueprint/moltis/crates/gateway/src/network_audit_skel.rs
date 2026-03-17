//! Network audit service layer.
//!
//! The buffer, filter, and stats types live in `moltis-network-filter`;
//! this module provides the `NetworkAuditService` trait (tied to gateway's
//! `ServiceResult`) and the live/noop implementations.

use std::path::PathBuf;

use {async_trait::async_trait, serde_json::Value, tracing::debug};

// Re-export types from the trusted-network crate so existing gateway code
// doesn't need to add a direct dependency when the feature is on.
#[cfg(feature = "trusted-network")]
pub use moltis_network_filter::{
    FilterOutcome, NetworkAuditEntry, NetworkProtocol,
    buffer::{NetworkAuditBuffer, NetworkAuditFilter, NetworkAuditStats},
};

use crate::services::ServiceResult;

// ── Service trait ───────────────────────────────────────────────────────────

#[async_trait]
pub trait NetworkAuditService: Send + Sync {
    async fn list(&self, params: Value) -> ServiceResult;
    async fn tail(&self, params: Value) -> ServiceResult;
    async fn stats(&self) -> ServiceResult;
    fn log_file_path(&self) -> Option<PathBuf>;
}

// ── Noop impl ───────────────────────────────────────────────────────────────

pub struct NoopNetworkAuditService;

#[async_trait]
impl NetworkAuditService for NoopNetworkAuditService {
    ...
}

// ── Live impl (requires trusted-network feature) ───────────────────────────

#[cfg(feature = "trusted-network")]
pub struct LiveNetworkAuditService {

#[cfg(feature = "trusted-network")]
impl LiveNetworkAuditService {
    /// Create a new service, spawning a background task that reads from the
    /// `mpsc::Receiver` and pushes entries into the buffer.
    pub fn new(
        mut rx: tokio::sync::mpsc::Receiver<NetworkAuditEntry>,
        file_path: PathBuf,
        capacity: usize,
    ) -> Self {

    /// Get a reference to the underlying buffer (for broadcasting).
    pub fn buffer(&self) -> &NetworkAuditBuffer {
    ...
}
}

#[cfg(feature = "trusted-network")]
#[async_trait]
impl NetworkAuditService for LiveNetworkAuditService {
    async fn list(&self, params: Value) -> ServiceResult {

    async fn tail(&self, params: Value) -> ServiceResult {
    ...
}

    async fn stats(&self) -> ServiceResult {
    ...
}

    fn log_file_path(&self) -> Option<PathBuf> {
    ...
}
}
