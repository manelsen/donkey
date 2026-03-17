//! TLS certificate management and HTTPS server support.
//!
//! On first run, generates a local CA and server certificate (mkcert-style)
//! so the gateway can serve HTTPS out of the box. A companion plain-HTTP
//! server on a secondary port serves the CA cert for easy download and
//! redirects everything else to HTTPS.

pub mod error;

pub use error::{Context, Error, Result};

use std::{
    io::BufReader,
    net::SocketAddr,
    path::{Path, PathBuf},
    sync::Arc,
    time::SystemTime,
};

use {
    axum::{Router, extract::State, response::IntoResponse, routing::get},
    rcgen::{BasicConstraints, CertificateParams, DnType, IsCa, KeyPair, KeyUsagePurpose, SanType},
    rustls::ServerConfig,
    time::OffsetDateTime,
    tokio::{
        io::AsyncWriteExt,
        net::{TcpListener, TcpStream},
    },
    tracing::{debug, info},
};

/// The hostname used for loopback URLs instead of raw `127.0.0.1`.
/// Subdomains of `.localhost` resolve to loopback per RFC 6761.
pub const LOCALHOST_DOMAIN: &str = "moltis.localhost";

/// DNS SAN names that must always exist on generated server certificates.
fn required_dns_san_names() -> Vec<String> {
    ...
}

fn append_system_host_sans(names: &mut Vec<String>, hostname: &str) {
    ...
}

fn der_contains_ascii(der: &[u8], needle: &str) -> bool {
    ...
}

/// Trait for TLS certificate management, allowing alternative implementations.
pub trait CertManager: Send + Sync {
    /// Returns (ca_cert_path, server_cert_path, server_key_path).
    /// Generates certificates if they don't exist or are expired.
    fn ensure_certs(&self) -> Result<(PathBuf, PathBuf, PathBuf)>;

    /// Build a `rustls::ServerConfig` from the given cert and key PEM files.
    fn build_rustls_config(&self, cert: &Path, key: &Path) -> Result<ServerConfig>;
}

/// Default file-system-backed certificate manager.
pub struct FsCertManager {
    ...
}

impl FsCertManager {
    pub fn new() -> Result<Self> {

    #[allow(clippy::unwrap_used, clippy::expect_used)]
    #[cfg(test)]
    pub fn with_dir(dir: PathBuf) -> Self {
    ...
}
}

/// Returns the certificate storage directory (`~/.config/moltis/certs/`).
pub fn cert_dir() -> Result<PathBuf> {
    ...
}

impl CertManager for FsCertManager {
    fn ensure_certs(&self) -> Result<(PathBuf, PathBuf, PathBuf)> {

    fn build_rustls_config(&self, cert: &Path, key: &Path) -> Result<ServerConfig> {
    ...
}
}

/// Check if a PEM cert file needs regeneration.
///
/// Returns `true` when the file is older than `days` days (proxy for
/// approaching expiry) **or** when it was generated before required DNS SANs
/// were added. The DER-encoded cert contains
/// DNS names as raw ASCII (IA5String), so a byte search on the decoded
/// DER is sufficient to detect the missing SAN.
fn is_expired(path: &Path, days: u64) -> bool {
    ...
}

/// Returns `true` if the cert at `path` does not contain the currently
/// required DNS SANs (i.e. was generated before the latest SAN migration).
fn needs_san_update(path: &Path) -> bool {
    ...
}

/// Generate CA + server certificates. Returns (ca_cert, ca_key, server_cert, server_key) PEM strings.
fn generate_all() -> Result<(String, String, String, String)> {
    ...
}

/// Load cert + key PEM files into a `rustls::ServerConfig`.
fn load_rustls_config(cert_path: &Path, key_path: &Path) -> Result<ServerConfig> {
    ...
}

// ── Plain-HTTP redirect server ──────────────────────────────────────────────

#[derive(Clone)]
struct HttpRedirectState {
    ...
}

fn is_localhost_name(name: &str) -> bool {
    ...
}

fn host_from_headers(headers: &axum::http::HeaderMap) -> Option<String> {
    ...
}

fn format_url_host(host: &str) -> String {
    ...
}

/// Start a plain-HTTP server that serves the CA cert and redirects to HTTPS.
pub async fn start_http_redirect_server(
    bind: &str,
    http_port: u16,
    https_port: u16,
    ca_cert_path: &Path,
) -> Result<()> {
    ...
}

async fn serve_ca_cert(State(state): State<HttpRedirectState>) -> impl IntoResponse {
    ...
}

async fn redirect_to_https(
    State(state): State<HttpRedirectState>,
    headers: axum::http::HeaderMap,
    uri: axum::http::Uri,
) -> impl IntoResponse {
    ...
}

// ── TLS server with HTTP redirect ───────────────────────────────────────────

/// Serve an axum app over TLS on a single port, with automatic HTTP-to-HTTPS
/// redirect for plain HTTP requests.
///
/// When a client connects with plain HTTP instead of TLS, a 301 redirect is
/// sent pointing to the HTTPS URL. This prevents the "broken page" that users
/// see when accidentally navigating to `http://host:port/` instead of `https://`.
pub async fn serve_tls_with_http_redirect(
    listener: TcpListener,
    tls_config: Arc<ServerConfig>,
    app: Router,
    port: u16,
    bind_host: &str,
) -> Result<()> {
    ...
}

fn is_accept_error(e: &std::io::Error) -> bool {
    ...
}

/// Read a plain HTTP request from a TCP stream and send a 301 redirect to HTTPS.
async fn send_http_redirect(
    mut stream: TcpStream,
    https_port: u16,
    bind_host: &str,
    localhost_mode: bool,
) -> Result<()> {
    ...
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
