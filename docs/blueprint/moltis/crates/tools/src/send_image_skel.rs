//! `send_image` tool — send a local image file to the current conversation's
//! channel (e.g. Telegram).
//!
//! Returns a `{ "screenshot": "data:{mime};base64,..." }` payload that the
//! chat runner picks up and routes through `send_screenshot_to_channels`.

use {
    async_trait::async_trait,
    base64::{Engine as _, engine::general_purpose::STANDARD as BASE64},
    moltis_agents::tool_registry::AgentTool,
    serde_json::{Value, json},
    std::{
        path::{Path, PathBuf},
        sync::Arc,
        time::Duration,
    },
    tracing::{debug, warn},
};

use crate::error::Error;

use crate::{exec::ExecOpts, sandbox::SandboxRouter};

/// 20 MB — Telegram's maximum photo upload size.
const MAX_FILE_SIZE: u64 = 20 * 1024 * 1024;
/// Enough for a 20 MB binary image encoded as base64 (~26.7 MB) plus margin.
const MAX_SANDBOX_OUTPUT_BYTES: usize = 32 * 1024 * 1024;
const SANDBOX_TOO_LARGE_PREFIX: &str = "__MOLTIS_SEND_IMAGE_TOO_LARGE__:";

/// Image-sending tool.
#[derive(Default)]
pub struct SendImageTool {
    ...
}

impl SendImageTool {
    #[must_use]
    pub fn new() -> Self {

    /// Attach a sandbox router for per-session dynamic sandbox resolution.
    pub fn with_sandbox_router(mut self, router: Arc<SandboxRouter>) -> Self {
    ...
}

    async fn read_host_file(path: &str) -> crate::Result<Vec<u8>> {
    ...
}

    async fn read_sandbox_file(
        router: &SandboxRouter,
        session_key: &str,
        path: &str,
    ) -> crate::Result<Vec<u8>> {
    ...
}

    async fn read_file_for_session(&self, session_key: &str, path: &str) -> crate::Result<Vec<u8>> {
    ...
}
}

/// Map a file extension to its MIME type.
fn mime_from_extension(ext: &str) -> Option<&'static str> {
    ...
}

#[async_trait]
impl AgentTool for SendImageTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

fn shell_single_quote(input: &str) -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    struct StubSandbox;

    #[async_trait]
    impl Sandbox for StubSandbox {
        fn backend_name(&self) -> &'static str {

        async fn ensure_ready(&self, _id: &SandboxId, _image_override: Option<&str>) -> Result<()> {
    ...
}

        async fn exec(
            &self,
            _id: &SandboxId,
            command: &str,
            _opts: &ExecOpts,
        ) -> Result<ExecResult> {
    ...
}

        async fn cleanup(&self, _id: &SandboxId) -> Result<()> {
    ...
}
    }

    #[test]
    fn mime_lookup_covers_supported_formats() {
    ...
}

    #[tokio::test]
    async fn rejects_missing_path_parameter() {
    ...
}

    #[tokio::test]
    async fn rejects_unsupported_extension() {
    ...
}

    #[tokio::test]
    async fn rejects_file_without_extension() {
    ...
}

    #[tokio::test]
    async fn rejects_nonexistent_file() {
    ...
}

    #[tokio::test]
    async fn rejects_directory() {
    ...
}

    #[tokio::test]
    async fn encodes_valid_png_as_data_uri() {
    ...
}

    #[tokio::test]
    async fn includes_caption_when_provided() {
    ...
}

    #[tokio::test]
    async fn encodes_ppm_as_data_uri() {
    ...
}

    #[tokio::test]
    async fn rejects_oversized_file() {
    ...
}

    #[tokio::test]
    async fn reads_sandbox_path_when_session_is_sandboxed() {
    ...
}

    #[tokio::test]
    async fn sandbox_missing_file_returns_sandbox_error() {
    ...
}
}
