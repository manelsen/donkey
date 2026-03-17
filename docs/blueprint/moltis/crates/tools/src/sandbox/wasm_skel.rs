//! WASM sandbox using Wasmtime + WASI for isolated execution.

#[cfg(feature = "wasm")]
use std::{collections::HashMap, path::PathBuf, sync::Arc};

#[cfg(feature = "wasm")]
use super::platform::parse_memory_limit;
#[cfg(feature = "wasm")]
use super::types::{
    HomePersistence, Sandbox, SandboxConfig, SandboxId, sanitize_path_component,
    truncate_output_for_display,
};
#[cfg(feature = "wasm")]
use crate::error::{Context, Error, Result};
#[cfg(feature = "wasm")]
use crate::exec::{ExecOpts, ExecResult};
#[cfg(feature = "wasm")]
use crate::wasm_engine::WasmComponentEngine;
#[cfg(feature = "wasm")]
use async_trait::async_trait;

// ---------------------------------------------------------------------------
// WASM sandbox (real Wasmtime + WASI isolation)
// ---------------------------------------------------------------------------

/// Real WASM sandbox that uses Wasmtime + WASI for isolated execution.
///
/// Two execution tiers:
/// - **Built-in commands** (~20 common coreutils): echo, cat, ls, mkdir, rm,
///   cp, mv, pwd, env, head, tail, wc, sort, touch, which, true, false,
///   test/[, basename, dirname.  These operate on a sandboxed directory tree.
/// - **WASM module execution**: `.wasm` files run via Wasmtime + WASI with
///   preopened dirs, fuel metering, epoch interruption, and captured I/O.
///
/// Unknown commands return exit code 127.
#[cfg(feature = "wasm")]
pub struct WasmSandbox {
    ...
}

#[cfg(feature = "wasm")]
impl WasmSandbox {
    pub fn new(config: SandboxConfig) -> Result<Self> {

    /// Default fuel limit: 1 billion instructions.
    pub(crate) fn fuel_limit(&self) -> u64 {
    ...
}

    /// Default epoch interval: 100ms.
    pub(crate) fn epoch_interval_ms(&self) -> u64 {
    ...
}

    /// Root directory for this sandbox instance's isolated filesystem.
    pub(crate) fn sandbox_root(&self, id: &SandboxId) -> PathBuf {
    ...
}

    /// Guest home directory inside the sandboxed filesystem.
    pub(crate) fn home_dir(&self, id: &SandboxId) -> PathBuf {
    ...
}

    /// Guest tmp directory inside the sandboxed filesystem.
    pub(crate) fn tmp_dir(&self, id: &SandboxId) -> PathBuf {
    ...
}

    /// Execute a `.wasm` module via Wasmtime + WASI with full isolation.
    async fn exec_wasm_module(
        &self,
        wasm_path: &std::path::Path,
        args: &[String],
        id: &SandboxId,
        opts: &ExecOpts,
    ) -> Result<ExecResult> {
    ...
}
}

#[cfg(feature = "wasm")]
#[async_trait]
impl Sandbox for WasmSandbox {
    fn backend_name(&self) -> &'static str {

    fn is_real(&self) -> bool {
    ...
}

    async fn ensure_ready(&self, id: &SandboxId, _image_override: Option<&str>) -> Result<()> {
    ...
}

    async fn exec(&self, id: &SandboxId, command: &str, opts: &ExecOpts) -> Result<ExecResult> {
    ...
}

    async fn cleanup(&self, id: &SandboxId) -> Result<()> {
    ...
}
}

// ---------------------------------------------------------------------------
// WASM built-in command interpreter
// ---------------------------------------------------------------------------

#[cfg(feature = "wasm")]
#[derive(Debug)]
enum CommandConnector {
    ...
}

#[cfg(feature = "wasm")]
#[derive(Debug)]
struct CommandSegment {
    ...
}

#[cfg(feature = "wasm")]
struct OutputRedirect {
    ...
}

#[cfg(feature = "wasm")]
struct WasmBuiltins;

#[cfg(feature = "wasm")]
impl WasmBuiltins {
    /// Parse a command line into segments separated by `&&`, `||`, and `;`.
    fn parse_command_line(input: &str) -> Vec<CommandSegment> {

    /// Expand `$VAR` references in arguments.
    fn expand_vars(args: &[String], env: &HashMap<String, String>) -> Vec<String> {
    ...
}

    /// Extract `>` or `>>` redirect from args, returning remaining args + redirect info.
    fn extract_redirect(args: &[String]) -> (Vec<String>, Option<OutputRedirect>) {
    ...
}

    /// Resolve a guest path to a host path within the sandbox root.
    /// Returns `None` if the path escapes the sandbox.
    fn resolve_guest_path(
        sandbox_root: &std::path::Path,
        guest_path: &str,
        guest_cwd: &str,
    ) -> Option<PathBuf> {
    ...
}

    /// Execute a built-in command. Returns exit code 127 for unknown commands.
    fn execute(
        name: &str,
        args: &[String],
        sandbox_root: &std::path::Path,
        env: &HashMap<String, String>,
    ) -> ExecResult {
    ...
}

    // --- Built-in command implementations ---

    fn cmd_echo(args: &[String]) -> ExecResult {
    ...
}

    fn cmd_cat(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_ls(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_mkdir(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_rm(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_cp(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_mv(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_env(env: &HashMap<String, String>) -> ExecResult {
    ...
}

    fn cmd_head(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_tail(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_wc(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_sort(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_touch(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_which(args: &[String]) -> ExecResult {
    ...
}

    fn cmd_test(args: &[String], sandbox_root: &std::path::Path) -> ExecResult {
    ...
}

    fn cmd_basename(args: &[String]) -> ExecResult {
    ...
}

    fn cmd_dirname(args: &[String]) -> ExecResult {
    ...
}
}
