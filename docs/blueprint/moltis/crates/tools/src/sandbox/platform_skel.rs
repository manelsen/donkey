//! Lightweight platform-specific sandbox backends.

use async_trait::async_trait;
#[cfg(target_os = "linux")]
use tracing::debug;

use {
    super::types::{Sandbox, SandboxConfig, SandboxId, truncate_output_for_display},
    crate::{
        error::{Error, Result},
        exec::{ExecOpts, ExecResult},
    },
};

/// Cgroup v2 sandbox using `systemd-run --user --scope` (Linux only, no root required).
#[cfg(target_os = "linux")]
pub struct CgroupSandbox {
    ...
}

#[cfg(target_os = "linux")]
impl CgroupSandbox {
    pub fn new(config: SandboxConfig) -> Self {

    fn scope_name(&self, id: &SandboxId) -> String {
    ...
}

    fn property_args(&self) -> Vec<String> {
    ...
}
}

#[cfg(target_os = "linux")]
#[async_trait]
impl Sandbox for CgroupSandbox {
    fn backend_name(&self) -> &'static str {

    async fn ensure_ready(&self, _id: &SandboxId, _image_override: Option<&str>) -> Result<()> {
    ...
}

    async fn exec(&self, id: &SandboxId, command: &str, opts: &ExecOpts) -> Result<ExecResult> {
    ...
}

    async fn cleanup(&self, id: &SandboxId) -> Result<()> {
    ...
}
}

/// Restricted host sandbox providing OS-level isolation (env clearing,
/// restricted PATH, rlimits) without containers or WASM. Commands run on the
/// host via `sh -c` with sanitised environment and ulimit wrappers.
pub struct RestrictedHostSandbox {
    ...
}

impl RestrictedHostSandbox {
    pub fn new(config: SandboxConfig) -> Self {

    /// Wrap a command with shell `ulimit` calls for resource isolation.
    fn build_ulimit_wrapped_command(&self, command: &str) -> String {
    ...
}
}

/// Parse a human-readable memory limit like "512M" or "1G" into bytes.
pub(crate) fn parse_memory_limit(s: &str) -> Option<u64> {
    ...
}

#[async_trait]
impl Sandbox for RestrictedHostSandbox {
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

/// Returns `true` when the WASM sandbox feature is compiled in.
#[cfg(feature = "wasm")]
pub fn is_wasm_sandbox_available() -> bool {
    ...
}

#[cfg(not(feature = "wasm"))]
pub fn is_wasm_sandbox_available() -> bool {
    ...
}
