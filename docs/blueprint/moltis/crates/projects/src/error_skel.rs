use std::{error::Error as StdError, path::PathBuf};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn command_execution(operation: &'static str, source: std::io::Error) -> Self {

    #[must_use]
    pub fn command_failed(operation: &'static str, stderr: impl Into<String>) -> Self {
    ...
}

    #[must_use]
    pub fn external<E>(context: impl Into<String>, source: E) -> Self
    where
        E: StdError + Send + Sync + 'static,
 {
}

pub type Result<T> = std::result::Result<T, Error>;
