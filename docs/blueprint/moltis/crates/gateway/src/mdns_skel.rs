//! mDNS/DNS-SD service advertisement for `_moltis._tcp`.
//!
//! Allows iOS (and other) clients on the same LAN to discover this gateway
//! automatically via Bonjour / mDNS browse.

use mdns_sd::{ServiceDaemon, ServiceInfo};

const SERVICE_TYPE: &str = "_moltis._tcp.local.";

fn alias_service_type(alias_slug: &str) -> Option<String> {
    ...
}

/// Register this gateway as a `_moltis._tcp` mDNS service.
///
/// Returns the [`ServiceDaemon`] handle — keep it alive for as long as the
/// service should be discoverable. Dropping it or calling [`shutdown`] will
/// unregister the service.
pub fn register(
    instance_name: &str,
    port: u16,
    version: &str,
    service_alias_slug: Option<&str>,
) -> anyhow::Result<ServiceDaemon> {
    ...
}

/// Gracefully unregister and shut down the mDNS daemon.
pub fn shutdown(daemon: &ServiceDaemon) {
    ...
}

#[cfg(test)]
#[allow(clippy::expect_used)]
mod tests {

    #[test]
    fn alias_service_type_uses_slug() {
    ...
}

    #[test]
    fn alias_service_type_ignores_empty_or_default() {
    ...
}

    #[test]
    fn register_and_shutdown_smoke() {
    ...
}

    #[test]
    fn register_with_unicode_instance_name() {
    ...
}
}
