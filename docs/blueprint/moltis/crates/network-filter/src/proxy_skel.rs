//! HTTP CONNECT proxy server with domain filtering.
//!
//! Handles both `CONNECT host:port` (HTTPS) and plain HTTP forward requests.
//! Connections from non-private IPs are rejected for security.

use std::{
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    sync::Arc,
};

use {
    tokio::{
        io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
        net::{TcpListener, TcpStream},
    },
    tracing::{debug, info, instrument, warn},
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, gauge, histogram};

use crate::{
    ApprovalSource, AuditSender, DomainDecision, FilterAction, FilterOutcome, NetworkAuditEntry,
    NetworkProtocol, Result, domain_approval::DomainApprovalManager,
};

// Re-export for convenience; canonical definition is in `types.rs`.
pub use crate::DEFAULT_PROXY_PORT;

/// HTTP CONNECT proxy server that filters outbound connections by domain.
///
/// The proxy handles:
/// - `CONNECT host:port` requests (used by HTTPS clients via `HTTPS_PROXY`)
/// - Plain HTTP requests forwarded via `HTTP_PROXY`
///
/// For each connection, the domain is checked against the `DomainApprovalManager`.
/// If the domain needs approval, the proxy holds the connection until a decision
/// is made (or timeout).
pub struct NetworkProxyServer {
    ...
}

impl NetworkProxyServer {
    pub fn new(
        listener_addr: SocketAddr,
        filter: Arc<DomainApprovalManager>,
        audit_tx: Option<AuditSender>,
    ) -> Self {

    /// Start the proxy server. This runs until the `shutdown` future completes.
    pub async fn run(&self, shutdown: tokio::sync::watch::Receiver<bool>) -> Result<()> {
    ...
}

    /// The address the proxy is listening on.
    pub fn addr(&self) -> SocketAddr {
    ...
}
}

/// Returns `true` if the IP is loopback or belongs to a private/link-local
/// range.  Used to reject connections from public IPs when the proxy binds
/// to `0.0.0.0` so container VMs on bridge/vmnet networks can reach it.
fn is_private_or_loopback(ip: &IpAddr) -> bool {
    ...
}

/// CGNAT / shared address space (100.64.0.0/10), also used by Tailscale.
fn is_cgnat(ip: Ipv4Addr) -> bool {
    ...
}

/// IPv6 Unique Local Address (fc00::/7).
fn is_ula(ip: Ipv6Addr) -> bool {
    ...
}

async fn shutdown_signal(rx: &tokio::sync::watch::Receiver<bool>) {
    ...
}

/// Handle a single client connection.
///
/// Reads the first line to determine if it's a CONNECT request or a plain HTTP request.
#[instrument(skip(stream, filter, audit_tx), fields(peer = %peer))]
async fn handle_client(
    stream: TcpStream,
    peer: SocketAddr,
    filter: Arc<DomainApprovalManager>,
    audit_tx: Option<AuditSender>,
) -> Result<()> {
    ...
}

async fn handle_client_inner(
    stream: TcpStream,
    peer: SocketAddr,
    filter: Arc<DomainApprovalManager>,
    audit_tx: Option<AuditSender>,
) -> Result<()> {
    ...
}

/// Send an audit entry on a best-effort basis (non-blocking, drop if channel full).
fn emit_audit(tx: &Option<AuditSender>, entry: NetworkAuditEntry) {
    ...
}

/// Handle an HTTP CONNECT tunnel request.
#[instrument(skip(reader, filter, audit_tx), fields(peer = %peer, target = %target))]
async fn handle_connect(
    mut reader: BufReader<TcpStream>,
    peer: SocketAddr,
    target: &str,
    filter: Arc<DomainApprovalManager>,
    audit_tx: Option<AuditSender>,
) -> Result<()> {
    ...
}

/// Handle a plain HTTP forward request (non-CONNECT).
///
/// Used when `HTTP_PROXY` is set and the client sends a full URL request.
#[instrument(skip(reader, filter, audit_tx), fields(peer = %peer, method = %method, target = %target))]
async fn handle_http_forward(
    mut reader: BufReader<TcpStream>,
    peer: SocketAddr,
    method: &str,
    target: &str,
    filter: Arc<DomainApprovalManager>,
    audit_tx: Option<AuditSender>,
) -> Result<()> {
    ...
}

/// Parse `host:port` from a CONNECT target. Defaults port to 443 if not specified.
fn parse_host_port(target: &str) -> (String, u16) {
    ...
}

/// Extract the hostname from an absolute HTTP URL.
fn extract_host_from_url(url: &str) -> Result<String> {
    ...
}

/// Extract the port from an absolute HTTP URL. Defaults to 80 for http, 443 for https.
fn extract_port_from_url(url: &str) -> u16 {
    ...
}

/// Convert an absolute URL to a relative path.
fn url_to_path(url: &str) -> String {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn test_extract_host_from_url() {
    ...
}

    #[test]
    fn test_extract_port_from_url() {
    ...
}

    #[test]
    fn test_url_to_path() {
    ...
}

    #[test]
    fn test_is_private_or_loopback() {
    ...
}
}
