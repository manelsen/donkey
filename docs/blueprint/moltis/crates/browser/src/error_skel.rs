//! Browser error types.

use std::error::Error as StdError;

use thiserror::Error;

/// Errors that can occur during browser operations.
#[derive(Debug, Error)]
pub enum Error {
    ...
}

/// Substrings that indicate the CDP WebSocket connection is dead.
const STALE_CONNECTION_PATTERNS: &[&str] = &[
    "receiver is gone",
    "oneshot canceled",
    "Request timed out",
    "Connection closed",
    "AlreadyClosed",
    "closed connection",
];

impl Error {
    /// Returns `true` when this error indicates the CDP connection to the
    /// browser is dead and the session should be recycled.
    pub fn is_connection_error(&self) -> bool {

    pub fn other(source: impl StdError + Send + Sync + 'static) -> Self {
    ...
}
}

impl From<chromiumoxide::error::CdpError> for Error {
    fn from(err: chromiumoxide::error::CdpError) -> Self {
}

#[cfg(test)]
mod tests {

    #[test]
    fn stale_connection_messages_detected() {
    ...
}

    #[test]
    fn normal_errors_are_not_connection_errors() {
    ...
}
}
