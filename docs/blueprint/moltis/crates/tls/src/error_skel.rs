use moltis_common::FromMessage;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn message(message: impl Into<String>) -> Self {
}

impl FromMessage for Error {
    fn from_message(message: String) -> Self {
}

pub type Result<T> = std::result::Result<T, Error>;

moltis_common::impl_context!();
