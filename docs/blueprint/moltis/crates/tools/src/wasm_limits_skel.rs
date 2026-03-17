use std::collections::HashMap;
#[cfg(feature = "wasm")]
use std::mem::size_of;

use serde::{Deserialize, Serialize};

const MB: u64 = 1024 * 1024;
const DEFAULT_MEMORY_BYTES: u64 = 16 * MB;
const DEFAULT_FUEL: u64 = 1_000_000;

/// Optional per-tool overrides for fuel and memory limits.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct ToolLimitOverride {
    ...
}

/// Runtime fuel/memory limits for WASM tools.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct WasmToolLimits {
    ...
}

impl Default for WasmToolLimits {
    fn default() -> Self {
}

impl WasmToolLimits {
    /// Resolve `(fuel, memory_bytes)` for a tool name.
    #[must_use]
    pub fn resolve(&self, tool_name: &str) -> (u64, u64) {

    /// Resolve `(fuel, memory_bytes_as_usize)` for store-level limits.
    #[must_use]
    pub fn resolve_store_limits(&self, tool_name: &str) -> (u64, usize) {
    ...
}
}

impl From<&moltis_config::schema::ToolLimitOverrideConfig> for ToolLimitOverride {
    fn from(value: &moltis_config::schema::ToolLimitOverrideConfig) -> Self {
}

impl From<&moltis_config::schema::WasmToolLimitsConfig> for WasmToolLimits {
    fn from(value: &moltis_config::schema::WasmToolLimitsConfig) -> Self {
}

/// Store resource limiter for WASM execution.
///
/// This limiter guards linear memory and table growth per store/invocation.
#[cfg(feature = "wasm")]
#[derive(Debug, Clone)]
pub struct WasmResourceLimiter {
    ...
}

#[cfg(feature = "wasm")]
impl WasmResourceLimiter {
    #[must_use]
    pub fn new(max_memory_bytes: usize) -> Self {

    #[cfg(test)]
    #[must_use]
    pub fn with_table_limit(max_memory_bytes: usize, max_table_elements: usize) -> Self {
    ...
}
}

#[cfg(feature = "wasm")]
impl wasmtime::ResourceLimiter for WasmResourceLimiter {
    fn memory_growing(
        &mut self,
        _current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> anyhow::Result<bool> {

    fn table_growing(
        &mut self,
        _current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> anyhow::Result<bool> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn config_deser_and_conversion() {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(all(test, feature = "wasm"))]
mod wasm_tests {

    #[test]
    fn table_growth_beyond_limit_rejected() {
    ...
}

    #[test]
    fn fuel_exhaustion_returns_error() {
    ...
}
}
