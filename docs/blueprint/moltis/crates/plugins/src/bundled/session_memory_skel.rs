//! `session-memory` hook: saves session conversation to a markdown file on `/new` or `/reset`.

use std::{path::PathBuf, sync::Arc};

use {
    async_trait::async_trait,
    tracing::{debug, info, warn},
};

use {
    moltis_common::{
        Result,
        hooks::{HookAction, HookEvent, HookHandler, HookPayload},
    },
    moltis_sessions::store::SessionStore,
};

/// Format current UTC date as YYYY-MM-DD.
fn utc_date_string() -> String {
    ...
}

#[must_use]
fn truncate_at_char_boundary(text: &str, max_bytes: usize) -> &str {
    ...
}

/// Saves session conversation log to `<workspace>/memory/session-<key>-<date>.md`
/// on session reset/new. The raw conversation is saved as markdown so the memory
/// system's chunker + embeddings will make it searchable.
pub struct SessionMemoryHook {
    ...
}

impl SessionMemoryHook {
    pub fn new(workspace_dir: PathBuf, session_store: Arc<SessionStore>) -> Self {

    pub fn with_max_messages(mut self, n: usize) -> Self {
    ...
}
}

#[async_trait]
impl HookHandler for SessionMemoryHook {
    fn name(&self) -> &str {

    fn events(&self) -> &[HookEvent] {
    ...
}

    async fn handle(&self, _event: HookEvent, payload: &HookPayload) -> Result<HookAction> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn ignores_non_new_commands() {
    ...
}

    #[tokio::test]
    async fn skips_empty_sessions() {
    ...
}

    #[tokio::test]
    async fn truncates_long_messages() {
    ...
}

    #[test]
    fn truncate_at_char_boundary_handles_multibyte_boundary() {
    ...
}
}
