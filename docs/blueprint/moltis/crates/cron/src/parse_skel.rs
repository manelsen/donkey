//! Parsing utilities for durations and absolute timestamps.

use crate::{Error, Result};

/// Parse a human-friendly duration string into milliseconds.
///
/// Supported suffixes: `s` (seconds), `m` (minutes), `h` (hours), `d` (days).
/// Examples: `"30s"`, `"5m"`, `"2h"`, `"1d"`.
pub fn parse_duration_ms(input: &str) -> Result<u64> {
    ...
}

/// Parse an ISO 8601 timestamp string into epoch milliseconds.
///
/// Accepts formats like `"2026-01-12T18:00:00Z"` or with timezone offset.
pub fn parse_absolute_time_ms(input: &str) -> Result<u64> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[rstest]
    #[case("")]
    #[case("100")]
    #[case("0s")]
    #[case("10x")]
    fn test_parse_duration_err(#[case] input: &str) {
    ...
}

    #[test]
    fn test_parse_iso_utc() {
    ...
}

    #[test]
    fn test_parse_iso_with_offset() {
    ...
}

    #[test]
    fn test_parse_iso_invalid() {
    ...
}
}
