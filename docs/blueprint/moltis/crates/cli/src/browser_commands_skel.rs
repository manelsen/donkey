//! CLI subcommands for browser configuration management.

use {anyhow::Result, clap::Subcommand};

#[derive(Subcommand)]
pub enum BrowserAction {
    ...
}

pub fn handle_browser(action: BrowserAction) -> Result<()> {
    ...
}

fn status() -> Result<()> {
    ...
}

fn enable() -> Result<()> {
    ...
}

fn disable() -> Result<()> {
    ...
}
