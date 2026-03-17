use thiserror::Error;

#[derive(Error, Debug)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn message(message: impl Into<String>) -> Self {

    #[must_use]
    pub fn other(source: impl std::error::Error + Send + Sync + 'static) -> Self {
    ...
}
}

impl FromMessage for Error {
    fn from_message(message: String) -> Self {
}

pub type MoltisError = Error;
pub type Result<T> = std::result::Result<T, Error>;

// ── Shared context trait ────────────────────────────────────────────────────

/// Trait for error types that can be constructed from a plain message string.
///
/// Implement this for your crate's error type, then invoke [`impl_context!`]
/// in your error module to get `.context()` and `.with_context()` on `Result`
/// and `Option`.
pub trait FromMessage: Sized {
    fn from_message(message: String) -> Self;
}

/// Generate a crate-local `Context` trait with `.context()` and `.with_context()`
/// methods on `Result` and `Option`.
///
/// Invoke inside a module that defines `Error: FromMessage` and
/// `type Result<T> = std::result::Result<T, Error>`.
///
/// ```ignore
/// // in crates/foo/src/error.rs
/// moltis_common::impl_context!();
/// ```
#[macro_export]
macro_rules! impl_context {
    ...
}
