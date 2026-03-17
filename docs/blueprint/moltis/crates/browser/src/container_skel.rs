//! Container management for sandboxed browser instances.
//!
//! Supports Docker, Podman, and Apple Container backends, auto-detecting the
//! best available option (Apple Container on macOS → Podman → Docker).

use std::{fmt::Display, process::Command};

use {
    crate::error::Error,
    tracing::{debug, info, warn},
};

type Result<T> = std::result::Result<T, Error>;

trait ContextExt<T> {
    fn context(self, context: impl Into<String>) -> Result<T>;

    fn with_context<C, F>(self, f: F) -> Result<T>
    where
        C: Into<String>,
        F: FnOnce() -> C;
}

impl<T, E> ContextExt<T> for std::result::Result<T, E>
where
    E: Display,
    ...
}

impl<T> ContextExt<T> for Option<T> {
    fn context(self, context: impl Into<String>) -> Result<T> {
    ...
}

    fn with_context<C, F>(self, f: F) -> Result<T>
    where
        C: Into<String>,
        F: FnOnce() -> C,
    {
        self.ok_or_else(|| Error::LaunchFailed(f().into()))
    }
}

fn browser_container_name_prefix(container_prefix: &str) -> String {
    ...
}

fn new_browser_container_name(container_prefix: &str) -> String {
    ...
}

/// Container backend type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContainerBackend {
    ...
}

impl ContainerBackend {
    /// Get the CLI command name for this backend.
    fn cli(&self) -> &'static str {
            #[cfg(target_os = "macos")]

    /// Check if this backend is available.
    fn is_available(&self) -> bool {
    ...
}
}

fn stop_container_by_id(backend: ContainerBackend, container_id: &str) {
    ...
}

/// A running browser container instance.
pub struct BrowserContainer {
    ...
}

impl BrowserContainer {
    /// Start a new browser container using the auto-detected backend.
    ///
    /// Returns a container instance with the host port for CDP connections.
    /// `container_host` is the hostname/IP used to reach the container (e.g.
    /// `"127.0.0.1"` on the host, `"host.docker.internal"` from inside Docker).
    /// When `profile_dir` is `Some`, the host directory is mounted into the
    /// container so that browser profile data persists across sessions.
    pub fn start(
        image: &str,
        container_prefix: &str,
        viewport_width: u32,
        viewport_height: u32,
        low_memory_threshold_mb: u64,
        session_timeout_ms: u64,
        profile_dir: Option<&std::path::Path>,
        container_host: &str,
    ) -> Result<Self> {

    /// Start a new browser container with a specific backend.
    pub fn start_with_backend(
        backend: ContainerBackend,
        image: &str,
        container_prefix: &str,
        viewport_width: u32,
        viewport_height: u32,
        low_memory_threshold_mb: u64,
        session_timeout_ms: u64,
        profile_dir: Option<&std::path::Path>,
        container_host: &str,
    ) -> Result<Self> {
    ...
}

    /// Get the WebSocket URL for CDP connection.
    #[must_use]
    pub fn websocket_url(&self) -> String {
    ...
}

    /// Get the HTTP URL for health checks.
    #[must_use]
    pub fn http_url(&self) -> String {
    ...
}

    /// Stop and remove the container.
    pub fn stop(&self) {
    ...
}

    /// Get the container ID.
    #[must_use]
    pub fn id(&self) -> &str {
    ...
}

    /// Get the backend being used.
    #[must_use]
    pub fn backend(&self) -> ContainerBackend {
    ...
}
}

impl Drop for BrowserContainer {
    fn drop(&mut self) {
}

/// Path inside the container where the browser profile is mounted.
const CONTAINER_PROFILE_PATH: &str = "/data/browser-profile";

/// Build the `DEFAULT_LAUNCH_ARGS` env-var value for containerised Chrome.
///
/// Always includes `--window-size`; appends low-memory flags when the host
/// system RAM is below the given threshold. Adds `--user-data-dir` when a
/// container-side profile path is provided.
fn build_container_launch_args(
    viewport_width: u32,
    viewport_height: u32,
    low_memory_threshold_mb: u64,
    container_profile_dir: Option<&str>,
    backend: ContainerBackend,
) -> String {
    ...
}

/// Compute the browserless container `TIMEOUT` (in ms) from pool lifecycle settings.
///
/// The result is `max(idle_timeout_secs, max_instance_lifetime_secs)` converted
/// to milliseconds, then floored against `navigation_timeout_ms` so that a single
/// long navigation cannot exceed the container's own timeout. The final value is
/// capped at `max_instance_lifetime_secs * 1000` to prevent disagree­ment with the
/// Moltis-side hard TTL when `navigation_timeout_ms` is very large.
pub(crate) fn browserless_session_timeout_ms(
    idle_timeout_secs: u64,
    navigation_timeout_ms: u64,
    max_instance_lifetime_secs: u64,
) -> u64 {
    ...
}

fn browserless_container_env(session_timeout_ms: u64) -> Vec<String> {
    ...
}

/// Start a Docker container for the browser.
fn start_oci_container(
    backend: ContainerBackend,
    image: &str,
    container_prefix: &str,
    host_port: u16,
    viewport_width: u32,
    viewport_height: u32,
    low_memory_threshold_mb: u64,
    session_timeout_ms: u64,
    profile_dir: Option<&std::path::Path>,
) -> Result<String> {
    ...
}

/// Start an Apple Container for the browser.
#[cfg(target_os = "macos")]
fn start_apple_container(
    image: &str,
    container_prefix: &str,
    host_port: u16,
    viewport_width: u32,
    viewport_height: u32,
    low_memory_threshold_mb: u64,
    session_timeout_ms: u64,
    profile_dir: Option<&std::path::Path>,
) -> Result<String> {
    ...
}

/// Detect the best available container backend.
///
/// Prefers Apple Container on macOS when available and functional (VM-isolated),
/// then Podman (daemonless), then Docker.
pub fn detect_backend() -> Result<ContainerBackend> {
    ...
}

/// Check if Apple Container is actually functional (has required plugins).
#[cfg(target_os = "macos")]
fn is_apple_container_functional() -> bool {
    ...
}

/// Check if a CLI tool is available.
fn is_cli_available(name: &str) -> bool {
    ...
}

/// Find an available TCP port.
fn find_available_port() -> Result<u16> {
    ...
}

/// Wait for the container to be ready by probing the Chrome DevTools endpoint.
///
/// TCP connectivity alone isn't sufficient - Chrome inside the container may accept
/// connections before it's ready to handle WebSocket requests. We probe `/json/version`
/// which browserless exposes when Chrome is truly ready.
fn wait_for_ready(host: &str, port: u16) -> Result<()> {
    ...
}

/// Probe the Chrome /json/version endpoint to check if it's ready.
fn probe_http_endpoint(host: &str, port: u16) -> Result<bool> {
    ...
}

/// Check if Docker is available.
#[must_use]
pub fn is_docker_available() -> bool {
    ...
}

/// Check if Apple Container is available and functional.
#[cfg(target_os = "macos")]
#[must_use]
pub fn is_apple_container_available() -> bool {
    ...
}

/// Check if any container runtime is available and functional.
#[must_use]
pub fn is_container_available() -> bool {
    ...
}

fn parse_docker_container_names(output: &[u8], container_prefix: &str) -> Vec<String> {
    ...
}

#[cfg(target_os = "macos")]
#[derive(serde::Deserialize)]
struct AppleContainerListEntry {
    ...
}

#[cfg(target_os = "macos")]
#[derive(serde::Deserialize)]
struct AppleContainerConfig {
    ...
}

#[cfg(target_os = "macos")]
fn parse_apple_container_names(output: &[u8]) -> Result<Vec<String>> {
    ...
}

#[cfg(target_os = "macos")]
fn parse_apple_container_names_for_prefix(
    output: &[u8],
    container_prefix: &str,
) -> Result<Vec<String>> {
    ...
}

fn cleanup_stale_docker_browser_containers(container_prefix: &str) -> Result<usize> {
    ...
}

#[cfg(target_os = "macos")]
fn cleanup_stale_apple_browser_containers(container_prefix: &str) -> Result<usize> {
    ...
}

#[cfg(target_os = "macos")]
fn cleanup_stale_apple_browser_containers_for_current_platform(
    container_prefix: &str,
) -> Result<usize> {
    ...
}

#[cfg(not(target_os = "macos"))]
fn cleanup_stale_apple_browser_containers_for_current_platform(
    _container_prefix: &str,
) -> Result<usize> {
    ...
}

/// Remove stale browser containers left behind by previous runs.
///
/// Browser containers are named with an instance-specific prefix so startup can
/// clean up orphaned instances before creating new ones.
pub fn cleanup_stale_browser_containers(container_prefix: &str) -> Result<usize> {
    ...
}

/// Pull the browser container image if not present.
/// Falls back to Docker if the primary backend fails.
pub fn ensure_image(image: &str) -> Result<()> {
    ...
}

/// Pull the browser container image using a specific backend.
pub fn ensure_image_with_backend(backend: ContainerBackend, image: &str) -> Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_new_browser_container_name_prefix() {
    ...
}

    #[test]
    fn test_parse_docker_container_names_filters_prefix() {
    ...
}

    #[cfg(target_os = "macos")]
    #[test]
    fn test_parse_apple_container_names_filters_prefix() {
    ...
}

    #[test]
    fn test_is_docker_available() {
    ...
}

    #[test]
    fn test_is_container_available() {
    ...
}

    #[test]
    fn test_docker_backend_cli() {
    ...
}

    #[cfg(target_os = "macos")]
    #[test]
    fn test_apple_container_backend_cli() {
    ...
}

    #[test]
    fn test_detect_backend_returns_some() {
    ...
}

    #[test]
    fn test_build_container_launch_args_without_low_memory() {
    ...
}

    #[test]
    fn test_build_container_launch_args_with_profile_dir() {
    ...
}

    #[test]
    fn test_build_container_launch_args_without_profile_dir() {
    ...
}

    #[cfg(target_os = "macos")]
    #[test]
    fn test_build_container_launch_args_apple_container_has_disable_shm() {
    ...
}

    #[test]
    fn test_build_container_launch_args_docker_no_disable_shm() {
    ...
}

    #[test]
    fn test_browserless_session_timeout_uses_moltis_lifecycle_floor() {
    ...
}

    #[test]
    fn test_browserless_session_timeout_caps_at_max_lifetime() {
    ...
}

    #[test]
    fn test_browserless_session_timeout_caps_large_navigation_timeout() {
    ...
}

    #[test]
    fn test_browserless_session_timeout_nav_within_ceiling() {
    ...
}

    #[test]
    fn test_browserless_container_env_includes_timeout() {
    ...
}
}
