use std::error::Error as StdError;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn external<E>(context: impl Into<String>, source: E) -> Self
    where
        E: StdError + Send + Sync + 'static,
 {
}

pub type Result<T> = std::result::Result<T, Error>;
