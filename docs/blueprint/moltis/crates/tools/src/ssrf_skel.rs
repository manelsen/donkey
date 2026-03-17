use std::net::{IpAddr, ToSocketAddrs};

use {crate::error::Error, url::Url};

use crate::Result;

/// Check if an IP is covered by an SSRF allowlist entry.
#[must_use]
pub fn is_ssrf_allowed(ip: &IpAddr, allowlist: &[ipnet::IpNet]) -> bool {
    ...
}

/// Check if an IP address is private, loopback, link-local, or otherwise
/// unsuitable for outbound fetches.
#[must_use]
pub fn is_private_ip(ip: &IpAddr) -> bool {
    ...
}

fn validate_ssrf_ips(host: &str, ips: &[IpAddr], allowlist: &[ipnet::IpNet]) -> Result<()> {
    ...
}

/// SSRF protection for async callers.
///
/// Resolves the URL host and rejects private/loopback/link-local IPs unless
/// explicitly allowlisted.
pub async fn ssrf_check(url: &Url, allowlist: &[ipnet::IpNet]) -> Result<()> {
    ...
}

/// SSRF protection for blocking callers.
pub fn ssrf_check_blocking(url: &Url, allowlist: &[ipnet::IpNet]) -> Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
