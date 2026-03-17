//! Shell-based hook handler that executes external commands.
//!
//! The handler spawns a child process for each event, passing the
//! [`HookPayload`] as JSON on stdin and interpreting the response:
//!
//! - Exit 0, no stdout → [`HookAction::Continue`]
//! - Exit 0, stdout JSON `{"action": "modify", "data": {...}}` → [`HookAction::ModifyPayload`]
//! - Exit 1 → [`HookAction::Block`] with stderr as reason
//! - Timeout → error (non-fatal, logged by registry)

use std::{collections::HashMap, path::PathBuf, time::Duration};

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    serde_json::Value,
    tokio::{io::AsyncWriteExt, process::Command},
    tracing::{debug, warn},
};

use {
    crate::hooks::{HookAction, HookEvent, HookHandler, HookPayload, ShellHookConfig},
    moltis_common::{Error as HookError, Result as HookResult},
};

/// Response format expected from shell hooks on stdout.
#[derive(Debug, Deserialize, Serialize)]
struct ShellHookResponse {
    ...
}

/// A hook handler that executes an external shell command.
pub struct ShellHookHandler {
    ...
}

impl ShellHookHandler {
    pub fn new(
        name: impl Into<String>,
        command: impl Into<String>,
        events: Vec<HookEvent>,
        timeout: Duration,
        env: HashMap<String, String>,
        working_dir: Option<PathBuf>,
    ) -> Self {

    /// Create from a [`ShellHookConfig`].
    ///
    /// Config-based hooks (from `moltis.toml`) don't have a hook directory,
    /// so `working_dir` is `None`.
    pub fn from_config(config: &ShellHookConfig) -> Self {
    ...
}
}

#[async_trait]
impl HookHandler for ShellHookHandler {
    fn name(&self) -> &str {

    fn events(&self) -> &[HookEvent] {
    ...
}

    async fn handle(&self, _event: HookEvent, payload: &HookPayload) -> HookResult<HookAction> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn shell_hook_continue_on_exit_zero() {
    ...
}

    #[tokio::test]
    async fn shell_hook_block_on_exit_one() {
    ...
}

    #[tokio::test]
    async fn shell_hook_modify_payload() {
    ...
}

    #[tokio::test]
    async fn shell_hook_receives_payload_on_stdin() {
    ...
}

    #[tokio::test]
    async fn shell_hook_timeout() {
    ...
}

    #[tokio::test]
    async fn shell_hook_env_vars() {
    ...
}

    #[tokio::test]
    async fn shell_hook_nonzero_exit_is_error() {
    ...
}

    #[tokio::test]
    async fn shell_hook_invalid_json_stdout_continues() {
    ...
}

    #[tokio::test]
    async fn shell_hook_working_dir() {
    ...
}

    #[tokio::test]
    async fn from_config_works() {
    ...
}
}
