//! Import memory files (MEMORY.md and all markdown files in `memory/`) from OpenClaw.

use std::path::Path;

use tracing::{debug, warn};

use crate::{
    detect::OpenClawDetection,
    report::{CategoryReport, ImportCategory, ImportStatus},
};

/// Import memory files from OpenClaw workspace to Moltis data directory.
///
/// - `MEMORY.md`: Merged if both exist (imported content appended with separator).
/// - `memory/*.md`: All markdown files copied, skipping files that already exist.
///   This includes daily logs (`YYYY-MM-DD.md`), project notes, and any other
///   custom memory files the user created.
///
/// Does NOT import the SQLite vector database (not portable across embedding models).
pub fn import_memory(detection: &OpenClawDetection, dest_data_dir: &Path) -> CategoryReport {
    ...
}

/// Import memory for a specific agent from a source workspace to a destination directory.
///
/// This is the core memory import logic, usable for both the default agent
/// (via `import_memory`) and non-default agents with per-agent workspaces.
pub fn import_agent_memory(source_workspace: &Path, dest_data_dir: &Path) -> CategoryReport {
    ...
}

enum MemoryFileResult {
    ...
}

const IMPORT_SEPARATOR: &str = "\n\n<!-- Imported from OpenClaw -->\n\n";

fn import_memory_file(src: &Path, dest: &Path) -> crate::error::Result<MemoryFileResult> {
    ...
}

/// Check if a filename looks like a daily log (YYYY-MM-DD.md).
fn looks_like_daily_log(name: &str) -> bool {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn import_new_memory_file() {
    ...
}

    #[test]
    fn import_merges_existing_memory() {
    ...
}

    #[test]
    fn import_idempotent_memory() {
    ...
}

    #[test]
    fn import_daily_logs() {
    ...
}

    #[test]
    fn import_all_markdown_memory_files() {
    ...
}

    #[test]
    fn daily_log_pattern_detection() {
    ...
}

    #[test]
    fn no_memory_returns_skipped() {
    ...
}
}
