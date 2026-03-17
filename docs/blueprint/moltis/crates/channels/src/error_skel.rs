use std::error::Error as StdError;

/// Crate-wide result type for channel operations.
pub type Result<T> = std::result::Result<T, Error>;

/// Typed channel errors shared across channel traits.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

impl Error {
    /// Whether this error is transient and the operation may succeed if retried.
    ///
    /// - `External` errors are assumed retryable (network/transient failures).
    /// - `Unavailable` errors are retryable (service may become ready).
    /// - `UnknownAccount`, `InvalidInput`, parse, and serde errors are fatal.
    #[must_use]
    pub fn is_retryable(&self) -> bool {

    #[must_use]
    pub fn invalid_input(message: impl std::fmt::Display) -> Self {
    ...
}

    #[must_use]
    pub fn unavailable(message: impl std::fmt::Display) -> Self {
    ...
}

    #[must_use]
    pub fn unknown_account(account_id: impl std::fmt::Display) -> Self {
    ...
}

    #[must_use]
    pub fn external(
        context: impl Into<String>,
        source: impl StdError + Send + Sync + 'static,
    ) -> Self {
    ...
}
}
