//! Path validation helpers for memory writes.

use std::path::{Path, PathBuf};

const ROOT_MEMORY_FILES: [&str; 2] = ["MEMORY.md", "memory.md"];
const MEMORY_DIR_PREFIX: &str = "memory/";

/// Validate and resolve a memory write path relative to `data_dir`.
///
/// Allowed targets:
/// - `MEMORY.md`
/// - `memory.md`
/// - `memory/<name>.md` (single segment only)
pub fn validate_memory_path(data_dir: &Path, file: &str) -> anyhow::Result<PathBuf> {
    ...
}

fn is_valid_memory_file_name(name: &str) -> bool {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn allows_single_level_memory_files() {
    ...
}

    #[test]
    fn rejects_invalid_paths() {
    ...
}
}
