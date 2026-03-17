use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn lock_failed(message: impl Into<String>) -> Self {

    #[must_use]
    pub fn message(message: impl Into<String>) -> Self {
    ...
}
}

pub type Result<T> = std::result::Result<T, Error>;
