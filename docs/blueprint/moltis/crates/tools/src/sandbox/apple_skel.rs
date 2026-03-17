//! Apple Container sandbox backend (macOS 26+, Apple Silicon).

#[cfg(target_os = "macos")]
use std::collections::HashMap;

#[cfg(target_os = "macos")]
use async_trait::async_trait;
use tracing::{debug, info, warn};

#[cfg(target_os = "macos")]
use tokio::sync::RwLock;

#[cfg(target_os = "macos")]
use super::containers::{
    apple_container_exec_args, apple_container_run_args, apple_container_status_from_inspect,
    is_apple_container_daemon_stale_error, is_apple_container_exists_error,
    is_apple_container_service_error, rebuildable_sandbox_image_tag, sandbox_image_dockerfile,
    sandbox_image_exists, sandbox_image_tag, unmark_zombie,
};
#[cfg(target_os = "macos")]
use super::host::provision_packages;
#[cfg(target_os = "macos")]
use super::paths::ensure_sandbox_home_persistence_host_dir;
#[cfg(target_os = "macos")]
use super::types::{
    BuildImageResult, DEFAULT_SANDBOX_IMAGE, NetworkPolicy, SANDBOX_HOME_DIR, Sandbox,
    SandboxConfig, SandboxId, canonical_sandbox_packages, truncate_output_for_display,
};
#[cfg(target_os = "macos")]
use crate::error::{Error, Result};
#[cfg(target_os = "macos")]
use crate::exec::{ExecOpts, ExecResult};

/// Apple Container sandbox using the `container` CLI (macOS 26+, Apple Silicon).
#[cfg(target_os = "macos")]
pub struct AppleContainerSandbox {
    ...
}

#[cfg(target_os = "macos")]
impl AppleContainerSandbox {
    pub fn new(config: SandboxConfig) -> Self {

    /// Detect the host gateway IP reachable from inside the container VM.
    /// Caches the result after the first successful probe.
    /// Falls back to `192.168.64.1` (default macOS vmnet gateway).
    async fn detect_host_gateway(&self, container_name: &str) -> String {
    ...
}

    fn image(&self) -> &str {
    ...
}

    fn container_prefix(&self) -> &str {
    ...
}

    fn base_container_name(&self, id: &SandboxId) -> String {
    ...
}

    pub(crate) async fn container_name(&self, id: &SandboxId) -> String {
    ...
}

    pub(crate) async fn bump_container_generation(&self, id: &SandboxId) -> String {
    ...
}

    fn image_repo(&self) -> &str {
    ...
}

    fn home_persistence_volume(&self, id: &SandboxId) -> Result<Option<String>> {
    ...
}

    async fn resolve_local_image(&self, requested_image: &str) -> Result<String> {
    ...
}

    /// Check whether the `container` CLI is available.
    pub async fn is_available() -> bool {
    ...
}

    async fn container_exists(name: &str) -> Result<bool> {
    ...
}

    async fn remove_container_force(name: &str) {
    ...
}

    async fn wait_for_container_absent(name: &str) {
    ...
}

    async fn wait_for_container_running(name: &str) -> Result<()> {
    ...
}

    async fn probe_container_exec_ready(name: &str) -> Result<()> {
    ...
}

    async fn wait_for_container_exec_ready(name: &str) -> Result<()> {
    ...
}

    async fn force_remove_and_wait(name: &str) {
    ...
}

    /// Inspect the container and return its current state.
    async fn inspect_container_state(name: &str) -> ContainerState {
    ...
}

    /// Try to create and start a container. Classifies errors into
    /// `CreateError` variants so the caller can decide the right recovery.
    async fn run_container(
        name: &str,
        image: &str,
        tz: Option<&str>,
        home_volume: Option<&str>,
    ) -> std::result::Result<(), CreateError> {
    ...
}

    /// Try to restart a stopped container. Returns `true` if restart succeeded.
    async fn try_restart_container(name: &str) -> bool {
    ...
}

    /// Capture the last N lines of container logs (stdout + stderr).
    /// Returns `None` if logs cannot be retrieved.
    async fn capture_container_logs(name: &str, max_lines: usize) -> Option<String> {
    ...
}

    /// Collect diagnostic information when all recovery attempts have failed.
    async fn diagnose_container_failure(name: &str) -> String {
    ...
}
}

/// State of an Apple Container as observed via `container inspect`.
#[cfg(any(target_os = "macos", test))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ContainerState {
    ...
}

/// Classification of container creation errors for recovery decisions.
#[cfg(target_os = "macos")]
#[derive(Debug)]
enum CreateError {
    ...
}

/// Check whether the Apple Container system service is running.
#[cfg(target_os = "macos")]
fn is_apple_container_service_running() -> bool {
    ...
}

/// Try to start the Apple Container system service.
/// Returns `true` if the service was successfully started.
#[cfg(target_os = "macos")]
fn try_start_apple_container_service() -> bool {
    ...
}

/// Ensure the Apple Container system service is running, starting it if needed.
/// Returns `true` if the service is running (either already or after starting).
#[cfg(target_os = "macos")]
pub fn ensure_apple_container_service() -> bool {
    ...
}

/// Restart the Apple Container daemon by stopping then starting it.
/// Used when the daemon is alive but its Virtualization.framework state is stale
/// (e.g. after an interrupted macOS restart/sleep). Returns `true` on success.
#[cfg(target_os = "macos")]
fn restart_apple_container_service() -> bool {
    ...
}

#[cfg(any(target_os = "macos", test))]
pub(crate) fn is_apple_container_unavailable_error(stderr: &str) -> bool {
    ...
}

#[cfg(any(target_os = "macos", test))]
pub(crate) fn should_restart_after_readiness_error(
    error_text: &str,
    state: ContainerState,
) -> bool {
    ...
}

/// Returns `true` when a freshly created container stopped immediately and
/// produced no meaningful logs. This indicates the VM never fully booted —
/// a broader symptom than the specific daemon-stale EINVAL signature. It can
/// occur after macOS sleep/wake cycles, resource exhaustion, or
/// Virtualization.framework glitches. The appropriate recovery is a full
/// service restart, same as for daemon-stale errors.
#[cfg(any(target_os = "macos", test))]
pub(crate) fn is_apple_container_boot_failure(logs: Option<&str>) -> bool {
    ...
}

#[cfg(target_os = "macos")]
#[async_trait]
impl Sandbox for AppleContainerSandbox {
    fn backend_name(&self) -> &'static str {

    async fn ensure_ready(&self, id: &SandboxId, image_override: Option<&str>) -> Result<()> {
    ...
}

    async fn exec(&self, id: &SandboxId, command: &str, opts: &ExecOpts) -> Result<ExecResult> {
    ...
}

    async fn build_image(
        &self,
        base: &str,
        packages: &[String],
    ) -> Result<Option<BuildImageResult>> {
    ...
}

    async fn cleanup(&self, id: &SandboxId) -> Result<()> {
    ...
}
}
