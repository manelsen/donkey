//! Typed parameter structs for complex session RPC methods.
//!
//! Only methods with non-trivial parameter shapes (multi-field with defaults,
//! null-vs-absent semantics, precedence logic) get dedicated structs here.
//! Simple key-only handlers use inline `.get(...)` directly.

use serde::Deserialize;

use crate::services::ServiceError;

/// Params for `session.patch`.
///
/// All fields except `key` are optional — only provided fields are updated.
///
/// Fields that can be cleared (set to null) use `Option<Option<String>>`:
/// - outer `None` → field was absent from the request (no-op)
/// - `Some(None)` → field was explicitly `null` (clear it)
/// - `Some(Some(v))` → field was set to value `v`
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PatchParams {
    ...
}

/// Deserialize a field as `Some(inner)` when present (even if null),
/// vs `None` when absent (via `#[serde(default)]`).
fn double_option<'de, T, D>(deserializer: D) -> Result<Option<Option<T>>, D::Error>
where
    T: Deserialize<'de>,
    D: serde::Deserializer<'de>,
{
    Ok(Some(Option::<T>::deserialize(deserializer)?))
}

/// Params for `session.voice_generate`.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VoiceGenerateParams {
    ...
}

impl VoiceGenerateParams {
    /// Resolve the target specification. `run_id` takes precedence.
    pub fn target(&self) -> Result<VoiceTarget, &'static str> {
}

/// How to locate the target assistant message for voice generation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VoiceTarget {
    ...
}

/// Parse a `serde_json::Value` into a typed param struct, mapping
/// deserialization errors to the service error format.
pub fn parse_params<T: serde::de::DeserializeOwned>(
    params: serde_json::Value,
) -> Result<T, ServiceError> {
    serde_json::from_value(params).map_err(ServiceError::message)
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
