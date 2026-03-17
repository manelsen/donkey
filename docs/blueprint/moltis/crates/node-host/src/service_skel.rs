//! Install / manage a headless node as an OS service.
//!
//! - **macOS**: launchd user agent (`~/Library/LaunchAgents/org.moltis.node.plist`)
//! - **Linux**: systemd user unit (`~/.config/systemd/user/moltis-node.service`)
//!
//! The service wraps `moltis node run` with the persisted connection parameters.

use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use {
    serde::{Deserialize, Serialize},
    tracing::{debug, info},
};

// ── Persisted connection config ────────────────────────────────────────────

/// Connection parameters saved to `~/.moltis/node.json` so the service can
/// start without CLI flags.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceConfig {
    ...
}

fn default_timeout() -> u64 {
    ...
}

impl ServiceConfig {
    /// Load from `<data_dir>/node.json`.
    pub fn load(data_dir: &Path) -> anyhow::Result<Self> {

    /// Save to `<data_dir>/node.json`.
    pub fn save(&self, data_dir: &Path) -> anyhow::Result<()> {
    ...
}
}

// ── Platform constants ─────────────────────────────────────────────────────

/// macOS launchd label.
const LAUNCHD_LABEL: &str = "org.moltis.node";

/// systemd user unit name.
const SYSTEMD_UNIT: &str = "moltis-node.service";

// ── Service actions ────────────────────────────────────────────────────────

/// Install the node as an OS service.
///
/// Saves the connection config, generates the service file, and enables it.
pub fn install(data_dir: &Path, config: &ServiceConfig) -> anyhow::Result<()> {
    ...
}

/// Uninstall the service and remove generated files.
pub fn uninstall(data_dir: &Path) -> anyhow::Result<()> {
    ...
}

/// Print the service status.
pub fn status() -> anyhow::Result<ServiceStatus> {
    ...
}

/// Stop the service.
pub fn stop() -> anyhow::Result<()> {
    ...
}

/// Restart the service.
pub fn restart() -> anyhow::Result<()> {
    ...
}

/// Print the service log path.
pub fn log_path(data_dir: &Path) -> PathBuf {
    ...
}

// ── Status type ────────────────────────────────────────────────────────────

#[derive(Debug)]
pub enum ServiceStatus {
    ...
}

impl std::fmt::Display for ServiceStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

// ── Binary resolution ──────────────────────────────────────────────────────

fn resolve_binary() -> anyhow::Result<PathBuf> {
    ...
}

// ── macOS launchd ──────────────────────────────────────────────────────────

fn launchd_plist_path() -> anyhow::Result<PathBuf> {
    ...
}

/// Escape a string for safe inclusion in XML text content.
fn xml_escape(s: &str) -> String {
    ...
}

/// Generate a launchd plist XML string.
///
/// `node run` reads connection parameters (gateway URL, device token, etc.)
/// from `~/.moltis/node.json` at runtime, so only `--timeout` is passed as
/// a CLI flag here.
pub fn generate_launchd_plist(
    moltis_bin: &Path,
    config: &ServiceConfig,
    log_path: &Path,
) -> String {
    ...
}

fn install_launchd(
    moltis_bin: &Path,
    config: &ServiceConfig,
    log_path: &Path,
) -> anyhow::Result<()> {
    ...
}

fn uninstall_launchd() -> anyhow::Result<()> {
    ...
}

fn status_launchd() -> anyhow::Result<ServiceStatus> {
    ...
}

fn stop_launchd() -> anyhow::Result<()> {
    ...
}

fn restart_launchd() -> anyhow::Result<()> {
    ...
}

// ── Linux systemd ──────────────────────────────────────────────────────────

fn systemd_unit_path() -> anyhow::Result<PathBuf> {
    ...
}

/// Generate a systemd user unit file.
pub fn generate_systemd_unit(moltis_bin: &Path, config: &ServiceConfig, log_path: &Path) -> String {
    ...
}

fn install_systemd(
    moltis_bin: &Path,
    config: &ServiceConfig,
    log_path: &Path,
) -> anyhow::Result<()> {
    ...
}

fn uninstall_systemd() -> anyhow::Result<()> {
    ...
}

fn status_systemd() -> anyhow::Result<ServiceStatus> {
    ...
}

fn stop_systemd() -> anyhow::Result<()> {
    ...
}

fn restart_systemd() -> anyhow::Result<()> {
    ...
}

fn run_systemctl(args: &[&str]) -> anyhow::Result<()> {
    ...
}

// ── Helpers ────────────────────────────────────────────────────────────────

fn home_dir() -> anyhow::Result<PathBuf> {
    ...
}

fn uid() -> u32 {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn service_config_save_and_load() {
    ...
}

    #[test]
    fn launchd_plist_contains_required_elements() {
    ...
}

    #[test]
    fn launchd_plist_escapes_xml_special_chars() {
    ...
}

    #[test]
    fn systemd_unit_contains_required_elements() {
    ...
}

    #[test]
    fn systemd_unit_only_passes_timeout_flag() {
    ...
}

    #[test]
    fn service_config_default_timeout() {
    ...
}

    #[test]
    fn status_display() {
    ...
}
}
