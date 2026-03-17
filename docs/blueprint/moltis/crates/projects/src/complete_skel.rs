use std::{fs, path::PathBuf};

/// Return directory completions for a partial path string.
///
/// Given a partial path like `/home/user/pro`, returns directories matching
/// that prefix (e.g. `/home/user/projects/`, `/home/user/proto/`).
pub fn complete_path(partial: &str) -> Vec<PathBuf> {
    ...
}

fn list_subdirs(dir: &PathBuf) -> Vec<PathBuf> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_complete_lists_subdirs() {
    ...
}

    #[test]
    fn test_complete_prefix_match() {
    ...
}
}
