//! Import MCP server configuration from OpenClaw.
//!
//! Merges OpenClaw's `mcp-servers.json` into Moltis's MCP registry,
//! skipping servers with duplicate names.

use std::{collections::HashMap, path::Path};

use tracing::debug;

use crate::{
    detect::OpenClawDetection,
    report::{CategoryReport, ImportCategory, ImportStatus},
    types::OpenClawMcpServer,
};

/// Import MCP servers from OpenClaw into the Moltis MCP registry.
///
/// `dest_mcp_path` is the path to Moltis's `mcp-servers.json`.
pub fn import_mcp_servers(detection: &OpenClawDetection, dest_mcp_path: &Path) -> CategoryReport {
    ...
}

fn load_mcp_servers(path: &Path) -> crate::error::Result<HashMap<String, OpenClawMcpServer>> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn import_new_mcp_servers() {
    ...
}

    #[test]
    fn import_merges_with_existing() {
    ...
}

    #[test]
    fn import_skips_duplicates() {
    ...
}

    #[test]
    fn no_mcp_file_returns_skipped() {
    ...
}
}
