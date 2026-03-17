//! Shared helpers for extracting typed parameters from `serde_json::Value`.
//!
//! These reduce boilerplate in `AgentTool::execute` implementations that
//! manually pull fields from a JSON object.

use serde_json::Value;

use crate::Error;

/// Extract a trimmed, non-empty `&str` from a JSON object field.
///
/// Returns `None` when the key is absent, null, not a string, empty,
/// or whitespace-only.
pub fn str_param<'a>(params: &'a Value, key: &str) -> Option<&'a str> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|v| !v.is_empty())
}

/// Try multiple keys in order and return the first non-empty string match.
pub fn str_param_any<'a>(params: &'a Value, keys: &[&str]) -> Option<&'a str> {
    keys.iter().find_map(|key| str_param(params, key))
}

/// Like [`str_param`] but returns a `crate::Error` when missing.
pub fn require_str<'a>(params: &'a Value, key: &str) -> crate::Result<&'a str> {
    str_param(params, key)
        .ok_or_else(|| Error::message(format!("missing required parameter: {key}")))
}

/// Extract a boolean, defaulting to `default` when absent.
pub fn bool_param(params: &Value, key: &str, default: bool) -> bool {
    ...
}

/// Extract a `u64`, defaulting to `default` when absent.
pub fn u64_param(params: &Value, key: &str, default: u64) -> u64 {
    ...
}

/// Extract an owned `String` from the first matching key.
pub fn owned_str_param(params: &Value, keys: &[&str]) -> Option<String> {
    ...
}

#[cfg(test)]
mod tests {
