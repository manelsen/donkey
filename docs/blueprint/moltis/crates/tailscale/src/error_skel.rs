#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn message(message: impl Into<String>) -> Self {
}

pub type Result<T> = std::result::Result<T, Error>;
