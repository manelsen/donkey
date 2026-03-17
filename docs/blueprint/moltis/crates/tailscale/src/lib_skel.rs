//! Tailscale Serve/Funnel integration.
//!
//! Shells out to the `tailscale` CLI to manage HTTPS proxying:
//! - **Serve**: exposes the gateway over HTTPS within the tailnet.
//! - **Funnel**: exposes the gateway to the public internet via Tailscale.

pub mod error;

pub use error::{Error, Result};

use std::net::IpAddr;

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    tracing::{info, warn},
};

// ── Types ────────────────────────────────────────────────────────────────────

/// Tailscale operating mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TailscaleMode {
    ...
}

impl TailscaleMode {
    pub fn as_str(&self) -> &'static str {
}

impl std::fmt::Display for TailscaleMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

impl std::str::FromStr for TailscaleMode {
    type Err = Error;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
}

/// Current tailscale status.
#[derive(Debug, Clone, Serialize)]
pub struct TailscaleStatus {
    ...
}

// ── Trait ─────────────────────────────────────────────────────────────────────

#[async_trait]
pub trait TailscaleManager: Send + Sync {
    /// Get current tailscale status.
    async fn status(&self) -> Result<TailscaleStatus>;
    /// Enable tailscale serve proxying to the given port.
    /// When `tls` is true, uses `https+insecure://` to connect to a local TLS server.
    async fn enable_serve(&self, port: u16, tls: bool) -> Result<()>;
    /// Enable tailscale funnel proxying to the given port.
    /// When `tls` is true, uses `https+insecure://` to connect to a local TLS server.
    async fn enable_funnel(&self, port: u16, tls: bool) -> Result<()>;
    /// Disable serve/funnel (reset).
    async fn disable(&self) -> Result<()>;
    /// Get the tailscale hostname for this machine.
    async fn hostname(&self) -> Result<Option<String>>;
}

// ── CLI-based implementation ─────────────────────────────────────────────────

/// Implementation that shells out to the `tailscale` CLI binary.
#[derive(Default)]
pub struct CliTailscaleManager;

impl CliTailscaleManager {
    ...
}

#[async_trait]
impl TailscaleManager for CliTailscaleManager {
    async fn status(&self) -> Result<TailscaleStatus> {

    async fn enable_serve(&self, port: u16, tls: bool) -> Result<()> {
    ...
}

    async fn enable_funnel(&self, port: u16, tls: bool) -> Result<()> {
    ...
}

    async fn disable(&self) -> Result<()> {
    ...
}

    async fn hostname(&self) -> Result<Option<String>> {
    ...
}
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Build the target URL for tailscale serve/funnel.
/// When the gateway uses TLS, tailscale needs `https+insecure://` to proxy to a
/// server with a self-signed certificate.
fn serve_target(port: u16, tls: bool) -> String {
    ...
}

/// Check if the serve status JSON indicates funnel is enabled.
fn has_funnel_enabled(val: &serde_json::Value) -> bool {
    ...
}

/// Returns true if the given address is a loopback address.
pub fn is_loopback_addr(addr: &str) -> bool {
    ...
}

/// Validate tailscale configuration constraints.
///
/// - When tailscale mode is not "off", the gateway must be bound to a loopback address.
/// - When funnel mode is requested, password auth must be set up (setup complete).
pub fn validate_tailscale_config(
    mode: TailscaleMode,
    bind_addr: &str,
    auth_setup_complete: bool,
) -> Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn mode_display() {
    ...
}

    #[test]
    fn loopback_check() {
    ...
}

    #[test]
    fn validate_off_always_ok() {
    ...
}

    #[test]
    fn validate_serve_requires_loopback() {
    ...
}

    #[test]
    fn validate_funnel_requires_password() {
    ...
}

    #[test]
    fn has_funnel_enabled_parsing() {
    ...
}
}
