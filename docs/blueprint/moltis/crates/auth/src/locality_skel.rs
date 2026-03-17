//! Connection locality detection for auth decisions.
//!
//! Determines whether a request is a direct local connection (no proxy)
//! based on headers, remote address, and proxy configuration.

use std::net::SocketAddr;

/// Returns `true` when common proxy/forwarding headers are present.
pub fn has_proxy_headers(headers: &axum::http::HeaderMap) -> bool {
    ...
}

/// Returns `true` when `host` (without port) is a loopback name/address.
fn is_loopback_host(host: &str) -> bool {
    ...
}

/// Determine whether a connection is a **direct local** connection (no proxy
/// in between).
///
/// When `behind_proxy` is `true`, the caller is known to be behind a reverse
/// proxy, so loopback source IPs are never treated as proof of a direct local
/// connection.
pub fn is_local_connection(
    headers: &axum::http::HeaderMap,
    remote_addr: SocketAddr,
    behind_proxy: bool,
) -> bool {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn has_proxy_headers_detects_x_real_ip() {
    ...
}

    #[test]
    fn has_proxy_headers_detects_cf_connecting_ip() {
    ...
}

    #[test]
    fn has_proxy_headers_detects_forwarded() {
    ...
}

    #[test]
    fn has_proxy_headers_empty() {
    ...
}

    #[test]
    fn is_loopback_host_variants() {
    ...
}

    #[test]
    fn local_connection_direct_loopback() {
    ...
}

    #[test]
    fn local_connection_with_proxy_headers() {
    ...
}

    #[test]
    fn local_connection_behind_proxy_override() {
    ...
}

    #[test]
    fn non_loopback_addr_not_local() {
    ...
}

    #[test]
    fn local_connection_ipv6_loopback() {
    ...
}

    #[test]
    fn local_connection_no_host_header() {
    ...
}

    #[test]
    fn not_local_when_xff_spoofs_loopback_value() {
    ...
}

    #[test]
    fn not_local_when_forwarded_spoofs_loopback_value() {
    ...
}

    #[test]
    fn not_local_when_host_is_external() {
    ...
}

    /// Simulates a reverse proxy (Caddy/nginx) on the same machine that
    /// does NOT add proxy headers (bare nginx `proxy_pass`). The Host header
    /// is rewritten to the upstream (loopback) address and the TCP source is
    /// loopback. Without `MOLTIS_BEHIND_PROXY`, this would appear local.
    #[test]
    fn bare_proxy_without_env_var_appears_local() {
    ...
}

    /// Typical Caddy/nginx with proper headers: loopback TCP but
    /// X-Forwarded-For reveals the real client IP.
    #[test]
    fn proxy_with_xff_detected() {
    ...
}

    /// Proxy that rewrites Host to a public domain (but no XFF).
    #[test]
    fn proxy_detected_via_host_header() {
    ...
}
}
