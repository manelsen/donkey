use std::error::Error as StdError;

use moltis_common::FromMessage;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn message(message: impl Into<String>) -> Self {

    #[must_use]
    pub fn external<E>(context: impl Into<String>, source: E) -> Self
    where
        E: StdError + Send + Sync + 'static,
 {
}

impl FromMessage for Error {
    fn from_message(message: String) -> Self {
}

pub type Result<T> = std::result::Result<T, Error>;

moltis_common::impl_context!();
