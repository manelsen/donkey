//! CLI subcommands for Tailscale Serve/Funnel management.

use {anyhow::Result, clap::Subcommand};

use moltis_gateway::tailscale::{
    CliTailscaleManager, TailscaleManager, TailscaleMode, validate_tailscale_config,
};

#[derive(Subcommand)]
pub enum TailscaleAction {
    ...
}

pub async fn handle_tailscale(action: TailscaleAction) -> Result<()> {
    ...
}
