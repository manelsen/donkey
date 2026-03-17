//! System information detection for local LLM inference.
//!
//! Detects available RAM and GPU capabilities to suggest appropriate models.

use sysinfo::System;

#[cfg(target_os = "macos")]
#[link(name = "Metal", kind = "framework")]
#[allow(unsafe_code)]
unsafe extern "C" {
    fn MTLCreateSystemDefaultDevice() -> *mut std::ffi::c_void;
}

/// System information for model selection.
#[derive(Debug, Clone)]
pub struct SystemInfo {
    ...
}

impl SystemInfo {
    /// Detect system information.
    pub fn detect() -> Self {

    /// Total RAM in gigabytes.
    #[must_use]
    pub fn total_ram_gb(&self) -> u32 {
    ...
}

    /// Available RAM in gigabytes.
    #[must_use]
    pub fn available_ram_gb(&self) -> u32 {
    ...
}

    /// Memory tier for model suggestions.
    #[must_use]
    pub fn memory_tier(&self) -> MemoryTier {
    ...
}

    /// Whether GPU acceleration is available.
    #[must_use]
    pub fn has_gpu(&self) -> bool {
    ...
}
}

#[cfg(target_os = "macos")]
#[must_use]
#[allow(unsafe_code)]
fn metal_runtime_available() -> bool {
    ...
}

#[cfg(not(target_os = "macos"))]
#[must_use]
const fn metal_runtime_available() -> bool {
    ...
}

/// Memory tier for model recommendations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryTier {
    ...
}

impl std::fmt::Display for MemoryTier {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// Parse `/proc/meminfo` as a fallback when `sysinfo` returns 0 (common in
/// Docker containers with restrictive cgroup settings).
///
/// Returns `(total_bytes, available_bytes)` or `None` if the file is absent or
/// unparseable.
fn read_proc_meminfo() -> Option<(u64, u64)> {
    ...
}

/// Parse a `/proc/meminfo` value line like `"   16384 kB"` into kilobytes.
fn parse_meminfo_kb(value: &str) -> Option<u64> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_ram_gb_conversion() {
    ...
}

    #[test]
    fn test_memory_tier() {
    ...
}

    #[test]
    fn test_has_gpu() {
    ...
}

    #[test]
    fn test_parse_meminfo_kb() {
    ...
}

    #[test]
    fn test_read_proc_meminfo_on_host() {
    ...
}

    #[test]
    fn test_apple_silicon_detection() {
    ...
}

    #[test]
    fn test_has_metal_detection_formula() {
    ...
}
}
