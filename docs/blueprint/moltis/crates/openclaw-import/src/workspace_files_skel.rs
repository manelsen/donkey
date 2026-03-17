//! Import workspace personality files from OpenClaw.
//!
//! Copies `SOUL.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `AGENTS.md`,
//! `HEARTBEAT.md`, and `BOOT.md` from the OpenClaw workspace directory to the
//! Moltis data directory, preserving any user-customized files at the destination.

use std::path::Path;

use tracing::{debug, warn};

use crate::{
    detect::OpenClawDetection,
    report::{CategoryReport, ImportCategory, ImportStatus},
};

/// The set of workspace personality files to import.
pub const WORKSPACE_FILE_NAMES: &[&str] = &[
    "SOUL.md",
    "IDENTITY.md",
    "USER.md",
    "TOOLS.md",
    "AGENTS.md",
    "HEARTBEAT.md",
    "BOOT.md",
];

/// Import workspace personality files from the default agent's workspace.
pub fn import_workspace_files(
    detection: &OpenClawDetection,
    dest_data_dir: &Path,
) -> CategoryReport {
    ...
}

/// Import workspace files for a specific agent from a source workspace
/// to a destination directory.
///
/// This is the core logic, usable for both the default agent
/// (via [`import_workspace_files`]) and non-default agents with per-agent
/// workspaces.
pub fn import_agent_workspace_files(source_workspace: &Path, dest_dir: &Path) -> CategoryReport {
    ...
}

enum FileImportResult {
    ...
}

fn import_single_file(
    src: &Path,
    dest: &Path,
    file_name: &str,
) -> crate::error::Result<FileImportResult> {
    ...
}

/// Check whether the destination file contains only the auto-seeded default.
///
/// Currently only `SOUL.md` has auto-seeding via `DEFAULT_SOUL` in
/// `moltis_config::loader`. For other files the function returns `false`
/// (they are only overwritten if empty).
fn is_default_content(file_name: &str, content: &str) -> bool {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn import_new_soul_file() {
    ...
}

    #[test]
    fn import_multiple_files() {
    ...
}

    #[test]
    fn skip_existing_customized_files() {
    ...
}

    #[test]
    fn replace_default_soul() {
    ...
}

    #[test]
    fn skip_empty_source_files() {
    ...
}

    #[test]
    fn no_workspace_files_returns_skipped() {
    ...
}

    #[test]
    fn import_per_agent_workspace_files() {
    ...
}

    #[test]
    fn replace_empty_destination() {
    ...
}

    #[test]
    fn idempotent_import() {
    ...
}
}
