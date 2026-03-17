//! Docker and Podman sandbox backends.

use {
    async_trait::async_trait,
    tracing::{debug, info, warn},
};

use {
    super::{
        containers::{
            rebuildable_sandbox_image_tag, sandbox_image_dockerfile, sandbox_image_exists,
            sandbox_image_tag,
        },
        host::provision_packages,
        paths::{ensure_sandbox_home_persistence_host_dir, host_visible_data_dir},
        types::{
            BuildImageResult, DEFAULT_SANDBOX_IMAGE, NetworkPolicy, SANDBOX_HOME_DIR, Sandbox,
            SandboxConfig, SandboxId, WorkspaceMount, canonical_sandbox_packages,
            truncate_output_for_display,
        },
    },
    crate::{
        error::{Error, Result},
        exec::{ExecOpts, ExecResult},
    },
};

/// Docker/Podman-based sandbox implementation.
///
/// The `cli` field selects the container CLI binary (`"docker"` or `"podman"`).
/// Podman's CLI is a drop-in replacement for Docker, so both backends share
/// this single implementation.
pub struct DockerSandbox {
    ...
}

impl DockerSandbox {
    pub fn new(config: SandboxConfig) -> Self {

    pub fn podman(config: SandboxConfig) -> Self {
    ...
}

    fn image(&self) -> &str {
    ...
}

    fn container_prefix(&self) -> &str {
    ...
}

    pub(crate) fn container_name(&self, id: &SandboxId) -> String {
    ...
}

    fn image_repo(&self) -> &str {
    ...
}

    pub(crate) fn resource_args(&self) -> Vec<String> {
    ...
}

    pub(crate) fn network_run_args(&self) -> Vec<String> {
    ...
}

    /// Resolve the IP that containers use to reach the host.
    ///
    /// Docker (and Podman >= 5.0) support the special `host-gateway` token in
    /// `--add-host`.  Older Podman versions reject it with:
    ///
    ///   Error: invalid IP address in add-host: "host-gateway"
    ///
    /// For those we resolve the address ourselves: rootless Podman (< 5.0) uses
    /// slirp4netns by default, which maps the host to `10.0.2.2`.  Rootful
    /// Podman uses a bridge whose gateway we can query via
    /// `podman network inspect`.
    pub(crate) fn resolve_host_gateway(&self) -> String {
    ...
}

    pub(crate) fn proxy_exec_env_args(&self) -> Vec<String> {
    ...
}

    /// Security hardening flags for `docker run`.
    ///
    /// `is_prebuilt` controls whether `--read-only` is applied: prebuilt images
    /// already have packages baked in so the root FS can be read-only, while
    /// non-prebuilt images need a writable root for `apt-get` provisioning.
    pub(crate) fn hardening_args(is_prebuilt: bool) -> Vec<String> {
    ...
}

    pub(crate) fn workspace_args(&self) -> Vec<String> {
    ...
}

    pub(crate) fn home_persistence_args(&self, id: &SandboxId) -> Result<Vec<String>> {
    ...
}

    async fn resolve_local_image(&self, requested_image: &str) -> Result<String> {
    ...
}
}

#[async_trait]
impl Sandbox for DockerSandbox {
    fn backend_name(&self) -> &'static str {

    async fn ensure_ready(&self, id: &SandboxId, image_override: Option<&str>) -> Result<()> {
    ...
}

    async fn build_image(
        &self,
        base: &str,
        packages: &[String],
    ) -> Result<Option<BuildImageResult>> {
    ...
}

    async fn exec(&self, id: &SandboxId, command: &str, opts: &ExecOpts) -> Result<ExecResult> {
    ...
}

    async fn cleanup(&self, id: &SandboxId) -> Result<()> {
    ...
}
}

/// No-op sandbox that passes through to direct execution.
pub struct NoSandbox;

#[async_trait]
impl Sandbox for NoSandbox {
    fn backend_name(&self) -> &'static str {

    fn is_real(&self) -> bool {
    ...
}

    async fn ensure_ready(&self, _id: &SandboxId, _image_override: Option<&str>) -> Result<()> {
    ...
}

    async fn exec(&self, _id: &SandboxId, command: &str, opts: &ExecOpts) -> Result<ExecResult> {
    ...
}

    async fn cleanup(&self, _id: &SandboxId) -> Result<()> {
    ...
}
}

/// Return `true` when the installed Podman version supports `host-gateway`
/// in `--add-host` (added in Podman 5.0).
pub(crate) fn podman_supports_host_gateway() -> bool {
    ...
}

/// Resolve the host IP that a Podman container (< 5.0) can use to reach the
/// host.  Rootless Podman defaults to slirp4netns where the host is always
/// `10.0.2.2`.  Rootful Podman uses a bridge network whose gateway we query
/// with `podman network inspect`.
pub(crate) fn podman_resolve_host_ip() -> Option<String> {
    ...
}
