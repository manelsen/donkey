//! `command-logger` hook: logs all Command events to a JSONL file.

use std::{path::PathBuf, sync::Mutex};

use {async_trait::async_trait, tracing::warn};

use moltis_common::{
    Result,
    hooks::{HookAction, HookEvent, HookHandler, HookPayload},
};

/// Appends JSONL entries for every `Command` event.
pub struct CommandLoggerHook {
    ...
}

impl CommandLoggerHook {
    pub fn new(log_path: PathBuf) -> Self {

    /// Default log path: `~/.moltis/logs/commands.log`
    pub fn default_path() -> Option<PathBuf> {
    ...
}

    fn ensure_file(&self) -> Result<()> {
    ...
}
}

#[async_trait]
impl HookHandler for CommandLoggerHook {
    fn name(&self) -> &str {

    fn events(&self) -> &[HookEvent] {
    ...
}

    async fn handle(&self, _event: HookEvent, payload: &HookPayload) -> Result<HookAction> {
    ...
}

    fn handle_sync(&self, _event: HookEvent, payload: &HookPayload) -> Result<HookAction> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn ignores_non_command_payloads() {
    ...
}
}
