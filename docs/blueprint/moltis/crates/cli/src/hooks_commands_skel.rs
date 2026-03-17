//! CLI commands for hook management.

use clap::Subcommand;

use moltis_plugins::{
    hook_discovery::{FsHookDiscoverer, HookDiscoverer},
    hook_eligibility::check_hook_eligibility,
};

#[derive(Subcommand)]
pub enum HookAction {
    ...
}

pub async fn handle_hooks(action: HookAction) -> anyhow::Result<()> {
    ...
}
