use {anyhow::Result, clap::Subcommand};

use moltis_config::validate::{self, Severity};

#[derive(Subcommand)]
pub enum ConfigAction {
    ...
}

pub async fn handle_config(action: ConfigAction) -> Result<()> {
    ...
}

/// ANSI color codes.
const RED: &str = "\x1b[31m";
const YELLOW: &str = "\x1b[33m";
const CYAN: &str = "\x1b[36m";
const BOLD: &str = "\x1b[1m";
const RESET: &str = "\x1b[0m";

fn check(verbose: bool) -> Result<()> {
    ...
}
