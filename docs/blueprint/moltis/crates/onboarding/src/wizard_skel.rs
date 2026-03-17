//! Terminal-based onboarding wizard using the shared state machine.

use std::io::{BufRead, Write};

use moltis_config::{MoltisConfig, find_or_default_config_path, save_config};

use crate::{Context, Result, state::WizardState};

/// Run the interactive onboarding wizard in the terminal.
pub async fn run_onboarding() -> Result<()> {
    ...
}
