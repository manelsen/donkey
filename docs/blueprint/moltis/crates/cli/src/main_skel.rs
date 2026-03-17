#[cfg(all(
    feature = "jemalloc",
    not(target_os = "windows"),
    not(all(target_os = "linux", target_arch = "aarch64"))
))]
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

/// Tune jemalloc to return unused pages to the OS faster, reducing RSS for
/// long-running processes. `dirty_decay_ms` and `muzzy_decay_ms` control how
/// aggressively freed pages are purged (lower = faster return to OS).
/// `background_thread:true` enables jemalloc's background thread for
/// asynchronous page purging without stalling allocation.
///
/// SAFETY: `export_name` overrides the well-known jemalloc configuration
/// symbol. There is exactly one definition in the program and the value is a
/// valid NUL-terminated C string.
#[cfg(all(
    feature = "jemalloc",
    not(target_os = "windows"),
    not(all(target_os = "linux", target_arch = "aarch64"))
))]
#[allow(unsafe_code, non_upper_case_globals)]
#[unsafe(export_name = "malloc_conf")]
static malloc_conf: &[u8] = b"dirty_decay_ms:1000,muzzy_decay_ms:1000,background_thread:true\0";

mod auth_commands;
mod browser_commands;
mod channel_commands;
mod config_commands;
mod db_commands;
mod doctor_commands;
mod hooks_commands;
#[cfg(feature = "openclaw-import")]
mod import_commands;
mod memory_commands;
mod node_commands;
mod sandbox_commands;
mod service_commands;
#[cfg(feature = "tailscale")]
mod tailscale_commands;

use {
    anyhow::anyhow,
    clap::{Parser, Subcommand},
    moltis_gateway::logs::{EnabledLogLevels, LogBroadcastLayer, LogBuffer},
    tracing::info,
    tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt},
};

#[derive(Parser)]
#[command(name = "moltis", about = "Moltis — personal AI gateway", version)]
struct Cli {
    ...
}

#[derive(Subcommand)]
enum Commands {
    ...
}

#[derive(Subcommand)]
enum SessionAction {
    ...
}

#[derive(Subcommand)]
enum SkillAction {
    ...
}

/// Initialise tracing and optionally attach a [`LogBroadcastLayer`] that
/// captures events into an in-memory ring buffer for the web UI.
fn init_telemetry(cli: &Cli, log_buffer: Option<LogBuffer>) {
    ...
}

#[cfg(feature = "tls")]
async fn trust_ca() -> anyhow::Result<()> {
    ...
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    ...
}

async fn handle_skills(action: SkillAction) -> anyhow::Result<()> {
    ...
}
