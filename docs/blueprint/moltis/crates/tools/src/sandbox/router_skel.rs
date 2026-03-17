//! Sandbox orchestration: backend selection, failover, routing.

use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use {
    async_trait::async_trait,
    tokio::sync::RwLock,
    tracing::{debug, warn},
};

#[cfg(target_os = "macos")]
use super::apple::{AppleContainerSandbox, ensure_apple_container_service};
#[cfg(feature = "wasm")]
use super::wasm::WasmSandbox;
use {
    super::{
        containers::{
            is_apple_container_corruption_error, is_cli_available, is_docker_daemon_available,
            should_use_docker_backend,
        },
        docker::{DockerSandbox, NoSandbox},
        platform::RestrictedHostSandbox,
        types::{
            BuildImageResult, DEFAULT_SANDBOX_IMAGE, Sandbox, SandboxConfig, SandboxId, SandboxMode,
        },
    },
    crate::{
        error::{Error, Result},
        exec::{ExecOpts, ExecResult},
    },
};

/// Wrapper sandbox that can fail over from a primary backend to a fallback backend.
///
/// This is used on macOS to fail over from Apple Container to Docker when the
/// Apple runtime enters a corrupted state (stale metadata, missing config.json,
/// service errors, etc.).
pub struct FailoverSandbox {
    ...
}

impl FailoverSandbox {
    pub fn new(primary: Arc<dyn Sandbox>, fallback: Arc<dyn Sandbox>) -> Self {

    async fn fallback_enabled(&self) -> bool {
    ...
}

    async fn switch_to_fallback(&self, error: &Error) {
    ...
}

    fn should_failover(&self, error: &Error) -> bool {
    ...
}
}

#[async_trait]
impl Sandbox for FailoverSandbox {
    fn backend_name(&self) -> &'static str {

    async fn ensure_ready(&self, id: &SandboxId, image_override: Option<&str>) -> Result<()> {
    ...
}

    async fn exec(&self, id: &SandboxId, command: &str, opts: &ExecOpts) -> Result<ExecResult> {
    ...
}

    async fn cleanup(&self, id: &SandboxId) -> Result<()> {
    ...
}

    async fn build_image(
        &self,
        base: &str,
        packages: &[String],
    ) -> Result<Option<BuildImageResult>> {
    ...
}
}

/// Create the appropriate sandbox backend based on config and platform.
pub fn create_sandbox(config: SandboxConfig) -> Arc<dyn Sandbox> {
    ...
}

/// Create a real sandbox backend regardless of mode (for use by SandboxRouter,
/// which may need a real backend even when global mode is Off because per-session
/// overrides can enable sandboxing dynamically).
pub(crate) fn create_sandbox_backend(config: SandboxConfig) -> Arc<dyn Sandbox> {
    ...
}

/// Select the sandbox backend based on config and platform availability.
///
/// When `backend` is `"auto"` (the default):
/// - On macOS, prefer Apple Container if the `container` CLI is installed
///   (each sandbox runs in a lightweight VM — stronger isolation than Docker).
/// - Prefer Podman (daemonless, rootless) over Docker when available.
/// - Fall back to Docker, then restricted-host otherwise.
pub(crate) fn select_backend(config: SandboxConfig) -> Arc<dyn Sandbox> {
    ...
}

/// Create a WASM sandbox backend, falling back to `RestrictedHostSandbox` if
/// the feature is disabled or initialisation fails.
fn create_wasm_backend(config: SandboxConfig) -> Arc<dyn Sandbox> {
    ...
}

/// Wrap a primary sandbox backend with a failover chain.
///
/// Tries Podman, then Docker as fallback, then restricted-host, returning the
/// primary unwrapped if no fallback runtime is available.
#[cfg(target_os = "macos")]
fn maybe_wrap_with_failover(primary: Arc<dyn Sandbox>, config: &SandboxConfig) -> Arc<dyn Sandbox> {
    ...
}

/// Check whether an error message indicates a Docker daemon connectivity issue.
pub(crate) fn is_docker_failover_error(message: &str) -> bool {
    ...
}

/// Check whether an error message indicates a Podman runtime issue that warrants
/// failover. Podman is daemonless so most Docker-daemon errors don't apply, but
/// socket/service errors or missing runtimes do.
pub(crate) fn is_podman_failover_error(message: &str) -> bool {
    ...
}

pub fn auto_detect_backend(config: SandboxConfig) -> Arc<dyn Sandbox> {
    ...
}

/// Events emitted by the sandbox subsystem for UI feedback.
#[derive(Debug, Clone)]
pub enum SandboxEvent {
    ...
}

/// Routes sandbox decisions per-session, with per-session overrides on top of global config.
pub struct SandboxRouter {
    ...
}

impl SandboxRouter {
    pub fn new(config: SandboxConfig) -> Self {

    /// Create a router with a custom sandbox backend (useful for testing).
    pub fn with_backend(config: SandboxConfig, backend: Arc<dyn Sandbox>) -> Self {
    ...
}

    /// Subscribe to sandbox lifecycle events.
    pub fn subscribe_events(&self) -> tokio::sync::broadcast::Receiver<SandboxEvent> {
    ...
}

    /// Emit a sandbox event. Silently drops if no subscribers.
    pub fn emit_event(&self, event: SandboxEvent) {
    ...
}

    /// Mark a session as preparing for sandbox first-run work.
    /// Returns `true` only the first time for a session key.
    pub async fn mark_preparing_once(&self, session_key: &str) -> bool {
    ...
}

    /// Clear preparation marker for a session (used on cleanup or prepare failure).
    pub async fn clear_prepared_session(&self, session_key: &str) {
    ...
}

    /// Check whether a session should run sandboxed.
    /// Returns `false` when no real container runtime is available, regardless of
    /// config mode or per-session overrides. Otherwise, per-session override takes
    /// priority, then falls back to global mode.
    pub async fn is_sandboxed(&self, session_key: &str) -> bool {
    ...
}

    /// Set a per-session sandbox override.
    pub async fn set_override(&self, session_key: &str, enabled: bool) {
    ...
}

    /// Remove a per-session override (revert to global mode).
    pub async fn remove_override(&self, session_key: &str) {
    ...
}

    /// Derive a SandboxId for a given session key.
    /// The key is sanitized for use as a container name (only alphanumeric, dash, underscore, dot).
    pub fn sandbox_id_for(&self, session_key: &str) -> SandboxId {
    ...
}

    /// Clean up sandbox resources for a session.
    pub async fn cleanup_session(&self, session_key: &str) -> Result<()> {
    ...
}

    /// Access the sandbox backend.
    pub fn backend(&self) -> &Arc<dyn Sandbox> {
    ...
}

    /// Access the global sandbox mode.
    pub fn mode(&self) -> &SandboxMode {
    ...
}

    /// Access the global sandbox config.
    pub fn config(&self) -> &SandboxConfig {
    ...
}

    /// Human-readable name of the sandbox backend (e.g. "docker", "apple-container").
    pub fn backend_name(&self) -> &'static str {
    ...
}

    /// Set a per-session image override.
    pub async fn set_image_override(&self, session_key: &str, image: String) {
    ...
}

    /// Remove a per-session image override.
    pub async fn remove_image_override(&self, session_key: &str) {
    ...
}

    /// Set a runtime override for the global default image.
    /// Pass `None` to revert to the config/hardcoded default.
    pub async fn set_global_image(&self, image: Option<String>) {
    ...
}

    /// Get the current effective default image (runtime override > config > hardcoded).
    pub async fn default_image(&self) -> String {
    ...
}

    /// Resolve the container image for a session.
    ///
    /// Priority (highest to lowest):
    /// 1. `skill_image` — from a skill's Dockerfile cache
    /// 2. Per-session override (`session.sandbox_image`)
    /// 3. Runtime global override (`set_global_image`)
    /// 4. Global config (`config.tools.exec.sandbox.image`)
    /// 5. Default constant (`DEFAULT_SANDBOX_IMAGE`)
    pub async fn resolve_image(&self, session_key: &str, skill_image: Option<&str>) -> String {
    ...
}
}
