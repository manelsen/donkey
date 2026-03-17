use std::collections::HashMap;

use crate::{Error, Result};

/// Parsed OAuth callback payload extracted from user-provided input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedCallbackInput {
    ...
}

/// Parse OAuth callback input copied from a browser or terminal.
///
/// Supported input formats:
/// - Full URL: `http://localhost:1455/auth/callback?code=...&state=...`
/// - Query string: `code=...&state=...`
/// - Compact token: `code#state`
pub fn parse_callback_input(raw: &str) -> Result<ParsedCallbackInput> {
    ...
}

fn parse_compact_code_state(value: &str) -> Option<(String, String)> {
    ...
}

fn parse_pairs(raw: Option<&str>) -> Option<ParsedCallbackInput> {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn parses_query_string() {
    ...
}

    #[test]
    fn parses_compact_code_state() {
    ...
}

    #[test]
    fn rejects_missing_state() {
    ...
}
}
