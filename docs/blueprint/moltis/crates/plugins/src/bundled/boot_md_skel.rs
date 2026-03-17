//! `boot-md` hook: reads `BOOT.md` from the workspace on `GatewayStart` and
//! feeds it as startup user message content.

use std::path::PathBuf;

use {
    async_trait::async_trait,
    tracing::{debug, info},
};

use moltis_common::{
    Result,
    hooks::{HookAction, HookEvent, HookHandler, HookPayload},
};

/// Reads workspace BOOT.md and injects its content on startup.
pub struct BootMdHook {
    ...
}

impl BootMdHook {
    pub fn new(workspace_dir: PathBuf) -> Self {
}

#[async_trait]
impl HookHandler for BootMdHook {
    fn name(&self) -> &str {

    fn events(&self) -> &[HookEvent] {
    ...
}

    fn priority(&self) -> i32 {
    ...
}

    async fn handle(&self, _event: HookEvent, _payload: &HookPayload) -> Result<HookAction> {
    ...
}
}

async fn read_non_empty_markdown(path: &std::path::Path) -> Result<Option<String>> {
    ...
}

fn strip_leading_html_comments(content: &str) -> &str {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn boot_md_missing_file_continues() {
    ...
}

    #[tokio::test]
    async fn boot_md_empty_file_continues() {
    ...
}

    #[tokio::test]
    async fn boot_md_comment_only_file_continues() {
    ...
}
}
