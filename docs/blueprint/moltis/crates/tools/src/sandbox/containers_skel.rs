//! Container image and container lifecycle management.

use std::collections::HashSet;

use {
    serde::Serialize,
    sha2::{Digest, Sha256},
    tracing::warn,
};

#[cfg(any(target_os = "macos", test))]
use super::types::APPLE_CONTAINER_SAFE_WORKDIR;
use {
    super::types::{
        GOGCLI_MODULE_PATH, GOGCLI_VERSION, SANDBOX_HOME_DIR, canonical_sandbox_packages,
    },
    crate::error::{Error, Result},
};

pub(crate) fn sandbox_image_dockerfile(base: &str, packages: &[String]) -> String {
    ...
}

#[cfg(any(target_os = "macos", test))]
const APPLE_CONTAINER_FALLBACK_SLEEP_SECONDS: u64 = 2_147_483_647;

#[cfg(any(target_os = "macos", test))]
fn apple_container_wrap_shell_command(shell_command: String) -> String {
    ...
}

#[cfg(any(target_os = "macos", test))]
pub(crate) fn apple_container_bootstrap_command() -> String {
    ...
}

#[cfg(any(target_os = "macos", test))]
pub(crate) fn apple_container_run_args(
    name: &str,
    image: &str,
    tz: Option<&str>,
    home_volume: Option<&str>,
) -> Vec<String> {
    ...
}

#[cfg(any(target_os = "macos", test))]
pub(crate) fn apple_container_exec_args(name: &str, shell_command: String) -> Vec<String> {
    ...
}

pub(crate) fn container_exec_shell_args(
    cli: &str,
    container_name: &str,
    shell_command: String,
) -> Vec<String> {
    ...
}

/// Compute the content-hash tag for a pre-built sandbox image.
/// Pure function — independent of any specific container CLI.
pub fn sandbox_image_tag(repo: &str, base: &str, packages: &[String]) -> String {
    ...
}

pub(crate) fn is_sandbox_image_tag(tag: &str) -> bool {
    ...
}

/// Return the deterministic image tag for the current sandbox config when the
/// requested image points to a local pre-built sandbox repository.
///
/// This allows recover-on-demand behavior when users delete local pre-built
/// images from the UI while Moltis is still running.
pub(crate) fn rebuildable_sandbox_image_tag(
    requested_image: &str,
    image_repo: &str,
    base_image: &str,
    packages: &[String],
) -> Option<String> {
    ...
}

/// OCI-compatible CLI binaries that use Docker-format commands
/// (`image ls`, `ps`, `system df`, etc.).
pub(crate) const OCI_COMPATIBLE_CLIS: &[&str] = &["docker", "podman"];

/// Check whether a container image exists locally.
/// `cli` is the container CLI binary (e.g. `"docker"`, `"podman"`, or `"container"`).
pub(crate) async fn sandbox_image_exists(cli: &str, tag: &str) -> bool {
    ...
}

/// Information about a locally cached sandbox image.
#[derive(Debug, Clone)]
pub struct SandboxImage {
    ...
}

/// List all local `<instance>-sandbox:*` images across available container CLIs.
pub async fn list_sandbox_images() -> Result<Vec<SandboxImage>> {
    ...
}

/// Extract size and created timestamp from Apple Container `image inspect` JSON.
async fn inspect_apple_container_image(tag: &str) -> (String, String) {
    ...
}

/// Format a byte count as a human-readable string (e.g. "361 MB").
pub(crate) fn format_bytes(bytes: u64) -> String {
    ...
}

/// Remove a specific `<instance>-sandbox:*` image.
pub async fn remove_sandbox_image(tag: &str) -> Result<()> {
    ...
}

/// Remove all local `<instance>-sandbox:*` images.
pub async fn clean_sandbox_images() -> Result<usize> {
    ...
}

// ── Running container management ─────────────────────────────────────────────

/// State of a running/stopped container.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ContainerRunState {
    ...
}

/// Which container backend manages this container.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ContainerBackend {
    ...
}

/// A container managed by moltis (running, stopped, or exited).
#[derive(Debug, Clone, Serialize)]
pub struct RunningContainer {
    ...
}

/// Containers that failed removal but are no longer truly present in the
/// runtime. These ghosts appear in `container list` after a failed
/// `container rm -f` and cannot be deleted until the daemon restarts.
/// Filtering them out of list results gives the UI a consistent view.
static ZOMBIE_CONTAINERS: std::sync::LazyLock<std::sync::RwLock<HashSet<String>>> =
    std::sync::LazyLock::new(|| std::sync::RwLock::new(HashSet::new()));

pub(crate) fn mark_zombie(name: &str) {
    ...
}

pub(crate) fn unmark_zombie(name: &str) {
    ...
}

pub(crate) fn clear_zombies() {
    ...
}

pub(crate) fn is_zombie(name: &str) -> bool {
    ...
}

/// List all containers whose name starts with `container_prefix`.
///
/// Queries both Apple Container and Docker backends when available,
/// merging results with the appropriate backend label.
pub async fn list_running_containers(container_prefix: &str) -> Result<Vec<RunningContainer>> {
    ...
}

/// Disk usage summary from the container runtime.
#[derive(Debug, Clone, Serialize)]
pub struct ContainerDiskUsage {
    ...
}

/// Query container runtime disk usage.
///
/// Uses `container system df --format json` for Apple Container,
/// falls back to `docker system df --format json` for Docker.
pub async fn container_disk_usage() -> Result<ContainerDiskUsage> {
    ...
}

/// Remove all containers whose name starts with `container_prefix`.
///
/// Returns the number of containers removed.
pub async fn clean_all_containers(container_prefix: &str) -> Result<usize> {
    ...
}

/// Stop a container by name. Detects the backend from the available CLIs.
///
/// Safety: callers must validate that `name` starts with the expected prefix
/// to prevent stopping arbitrary containers.
pub async fn stop_container(name: &str) -> Result<()> {
    ...
}

/// Remove a container by name (force). Detects the backend from available CLIs.
///
/// Safety: callers must validate that `name` starts with the expected prefix
/// to prevent removing arbitrary containers.
pub async fn remove_container(name: &str) -> Result<()> {
    ...
}

/// Restart the container daemon. For Apple Container this runs
/// `container system stop` followed by `container system start`.
/// For Docker it runs `docker restart` on the Docker daemon socket
/// (equivalent to `systemctl restart docker` but works cross-platform).
///
/// This clears ghost containers and corrupted daemon state.
pub async fn restart_container_daemon() -> Result<()> {
    ...
}

pub(crate) fn apple_container_status_from_inspect(stdout: &str) -> Option<&'static str> {
    ...
}

pub(crate) fn is_apple_container_service_error(stderr: &str) -> bool {
    ...
}

pub(crate) fn is_apple_container_exists_error(stderr: &str) -> bool {
    ...
}

pub(crate) fn is_apple_container_daemon_stale_error(text: &str) -> bool {
    ...
}

pub(crate) fn is_apple_container_corruption_error(stderr: &str) -> bool {
    ...
}

pub(crate) fn should_use_docker_backend(
    docker_cli_available: bool,
    docker_daemon_available: bool,
) -> bool {
    ...
}

pub(crate) fn is_docker_daemon_available() -> bool {
    ...
}

/// Check whether a CLI tool is available on PATH.
pub(crate) fn is_cli_available(name: &str) -> bool {
    ...
}
