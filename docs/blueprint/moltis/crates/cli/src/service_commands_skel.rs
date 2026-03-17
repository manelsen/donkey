//! `moltis service` subcommands — install/manage the gateway as an OS service.
//!
//! - **macOS**: launchd user agent (`~/Library/LaunchAgents/org.moltis.plist`)
//! - **Linux**: systemd user unit (`~/.config/systemd/user/moltis.service`)

use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use {anyhow::Result, clap::Subcommand};

/// `moltis service` subcommands.
#[derive(Subcommand)]
pub enum ServiceAction {
    ...
}

pub fn handle_service(action: ServiceAction) -> Result<()> {
    ...
}

// ── Types ──────────────────────────────────────────────────────────────────

struct GatewayServiceOpts {
    ...
}

// ── Status ─────────────────────────────────────────────────────────────────

enum ServiceStatus {
    ...
}

impl std::fmt::Display for ServiceStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

// ── Binary resolution ──────────────────────────────────────────────────────

fn resolve_binary() -> Result<PathBuf> {
    ...
}

fn home_dir() -> Result<PathBuf> {
    ...
}

fn uid() -> u32 {
    ...
}

// ── macOS launchd ──────────────────────────────────────────────────────────

const LAUNCHD_LABEL: &str = "org.moltis.gateway";
const SYSTEMD_UNIT: &str = "moltis.service";

fn launchd_plist_path() -> Result<PathBuf> {
    ...
}

fn generate_launchd_plist(moltis_bin: &Path, opts: &GatewayServiceOpts, log_path: &Path) -> String {
    ...
}

fn install_launchd(moltis_bin: &Path, opts: &GatewayServiceOpts, log_path: &Path) -> Result<()> {
    ...
}

fn uninstall_launchd() -> Result<()> {
    ...
}

fn status_launchd() -> Result<ServiceStatus> {
    ...
}

fn stop_launchd() -> Result<()> {
    ...
}

fn restart_launchd() -> Result<()> {
    ...
}

// ── Linux systemd ──────────────────────────────────────────────────────────

fn systemd_unit_path() -> Result<PathBuf> {
    ...
}

fn generate_systemd_unit(moltis_bin: &Path, opts: &GatewayServiceOpts, log_path: &Path) -> String {
    ...
}

fn install_systemd(moltis_bin: &Path, opts: &GatewayServiceOpts, log_path: &Path) -> Result<()> {
    ...
}

fn uninstall_systemd() -> Result<()> {
    ...
}

fn status_systemd() -> Result<ServiceStatus> {
    ...
}

fn stop_systemd() -> Result<()> {
    ...
}

fn restart_systemd() -> Result<()> {
    ...
}

fn run_systemctl(args: &[&str]) -> Result<()> {
    ...
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {

    #[test]
    fn launchd_plist_with_bind_and_port() {
    ...
}

    #[test]
    fn launchd_plist_omits_optional_flags() {
    ...
}

    #[test]
    fn systemd_unit_basic() {
    ...
}

    #[test]
    fn systemd_unit_with_bind_and_port() {
    ...
}

    #[test]
    fn systemd_unit_omits_optional_flags() {
    ...
}

    #[test]
    fn status_display() {
    ...
}
}
