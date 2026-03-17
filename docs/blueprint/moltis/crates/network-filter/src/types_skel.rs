//! Core types for trusted-network domain filtering and audit logging.
//!
//! These types are shared between the proxy (emits entries), the gateway
//! (buffer, persistence, UI streaming), and the macOS Swift bridge.

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    time::OffsetDateTime,
};

/// The default port the proxy listens on inside the trusted network.
pub const DEFAULT_PROXY_PORT: u16 = 18791;

// ── Network policy ──────────────────────────────────────────────────────────

/// Network policy for sandboxed containers.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum NetworkPolicy {
    ...
}

// ── Audit entry ─────────────────────────────────────────────────────────────

/// A single audited network request or connection through the proxy.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkAuditEntry {
    ...
}

/// The proxy protocol used for a connection.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum NetworkProtocol {
    ...
}

/// The outcome of the domain filter check.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FilterOutcome {
    ...
}

/// How a domain was approved.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ApprovalSource {
    ...
}

/// Type alias for the sender half of the audit channel.
///
/// The gateway creates the channel; the proxy uses this to emit entries.
pub type AuditSender = tokio::sync::mpsc::Sender<NetworkAuditEntry>;

impl std::fmt::Display for NetworkProtocol {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl std::fmt::Display for FilterOutcome {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

// ── Domain filtering ────────────────────────────────────────────────────────

/// Action returned by the domain filter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FilterAction {
    ...
}

/// Trait for checking whether a domain should be allowed through the proxy.
#[async_trait]
pub trait DomainFilter: Send + Sync {
    async fn check(&self, session: &str, domain: &str) -> FilterAction;
}

/// A pattern for matching domain names.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DomainPattern {
    ...
}

impl DomainPattern {
    /// Parse a pattern string into a `DomainPattern`.
    pub fn parse(s: &str) -> Self {

    /// Check whether a domain matches this pattern.
    pub fn matches(&self, domain: &str) -> bool {
    ...
}
}

/// Outcome of a domain approval request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DomainDecision {
    ...
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn serde_http_forward_entry() {
    ...
}

    #[test]
    fn serde_denied_entry() {
    ...
}

    #[test]
    fn protocol_display() {
    ...
}

    #[test]
    fn filter_outcome_display() {
    ...
}

    #[test]
    fn enum_serde_rename() {
    ...
}

    // -- DomainPattern ---

    #[test]
    fn domain_pattern_exact() {
    ...
}

    #[test]
    fn domain_pattern_wildcard_subdomain() {
    ...
}

    #[test]
    fn domain_pattern_wildcard() {
    ...
}

    #[test]
    fn domain_pattern_case_insensitive() {
    ...
}

    // -- NetworkPolicy ---

    #[test]
    fn network_policy_default_is_trusted() {
    ...
}

    #[test]
    fn network_policy_serde() {
    ...
}
}
