use std::path::{Path, PathBuf};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn invalid_hook_metadata(path: &Path, reason: impl Into<String>) -> Self {

    #[must_use]
    pub fn message(message: impl Into<String>) -> Self {
    ...
}

    #[must_use]
    pub fn external(
        context: impl Into<String>,
        source: impl std::error::Error + Send + Sync + 'static,
    ) -> Self {
    ...
}
}

pub type Result<T> = std::result::Result<T, Error>;
