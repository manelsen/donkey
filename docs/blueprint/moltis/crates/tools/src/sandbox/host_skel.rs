//! Host package provisioning (Debian/Ubuntu apt-get).

use tracing::{info, warn};

use {
    super::containers::{container_exec_shell_args, is_cli_available},
    crate::error::Result,
};

/// Install configured packages inside a container via `apt-get`.
///
/// `cli` is the container CLI binary name (e.g. `"docker"` or `"container"`).
pub(crate) async fn provision_packages(
    cli: &str,
    container_name: &str,
    packages: &[String],
) -> Result<()> {
    ...
}

/// Check whether the current process is running as root (UID 0).
pub(crate) fn is_running_as_root() -> bool {
    ...
}

/// Check whether the current host is Debian/Ubuntu (has `/etc/debian_version`
/// and `apt-get` on PATH).
pub fn is_debian_host() -> bool {
    ...
}

pub(crate) fn host_package_name_candidates(pkg: &str) -> Vec<String> {
    ...
}

async fn is_installed_dpkg_package(pkg: &str) -> bool {
    ...
}

async fn resolve_installed_host_package(pkg: &str) -> Option<String> {
    ...
}

async fn is_apt_package_available(pkg: &str) -> bool {
    ...
}

async fn resolve_installable_host_package(pkg: &str) -> Option<String> {
    ...
}

/// Result of host package provisioning.
#[derive(Debug, Clone)]
pub struct HostProvisionResult {
    ...
}

/// Install configured packages directly on the host via `apt-get`.
///
/// Used when the sandbox backend is `"none"` (no container runtime) and the
/// host is Debian/Ubuntu. Returns `None` if packages are empty or the host
/// is not Debian-based.
///
/// This is **non-fatal**: failures are logged as warnings and do not block
/// startup.
#[tracing::instrument(skip(packages), fields(package_count = packages.len()))]
pub async fn provision_host_packages(packages: &[String]) -> Result<Option<HostProvisionResult>> {
    ...
}
