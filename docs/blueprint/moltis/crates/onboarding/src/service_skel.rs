//! Live onboarding service that backs the `wizard.*` RPC methods.

use std::{path::PathBuf, sync::Mutex};

use {
    serde_json::{Value, json},
    tracing::info,
};

use moltis_config::{AgentIdentity, MoltisConfig, UserProfile};

use crate::{
    Context, Result,
    state::{WizardState, WizardStep},
};

/// Live onboarding service backed by a `WizardState` and config persistence.
pub struct LiveOnboardingService {
    ...
}

impl LiveOnboardingService {
    pub fn new(config_path: PathBuf) -> Self {

    /// Save config to the service's config path.
    fn save(&self, config: &MoltisConfig) -> Result<()> {
    ...
}

    /// Check whether onboarding has been completed.
    ///
    /// Returns `true` when the `.onboarded` sentinel file exists in the data
    /// directory (written after the wizard finishes) **or** the
    /// `SKIP_ONBOARDING` environment variable is set to a non-empty value.
    /// Pre-existing identity/user data alone no longer auto-skips.
    fn is_already_onboarded(&self) -> bool {
    ...
}

    /// Mark onboarding as complete by writing the sentinel file.
    fn mark_onboarded(&self) {
    ...
}

    /// Start the wizard. Returns current step info.
    ///
    /// If `force` is true, the wizard starts even when already onboarded,
    /// allowing the user to reconfigure their identity.
    pub fn wizard_start(&self, force: bool) -> Value {
    ...
}

    /// Advance the wizard with user input.
    pub fn wizard_next(&self, input: &str) -> Result<Value> {
    ...
}

    /// Cancel an active wizard session.
    pub fn wizard_cancel(&self) {
    ...
}

    /// Return the current wizard status.
    pub fn wizard_status(&self) -> Value {
    ...
}

    /// Update identity fields by merging partial JSON into the existing config.
    ///
    /// Accepts: `{name?, emoji?, theme?, soul?, user_name?, user_timezone?}`
    /// Also accepts `"creature"` and `"vibe"` as backward-compat aliases for `"theme"`.
    pub fn identity_update(&self, params: Value) -> Result<Value> {
    ...
}

    /// Update SOUL.md for the main agent.
    pub fn identity_update_soul(&self, soul: Option<String>) -> Result<Value> {
    ...
}

    /// Read identity from the config file (for `agent.identity.get`).
    pub fn identity_get(&self) -> moltis_config::ResolvedIdentity {
    ...
}
}

/// Path to the `.onboarded` sentinel file in the data directory.
fn onboarded_sentinel() -> PathBuf {
    ...
}

fn merge_identity(dst: &mut AgentIdentity, src: &AgentIdentity) {
    ...
}

fn merge_user(dst: &mut UserProfile, src: &UserProfile) {
    ...
}

fn step_response(ws: &WizardState) -> Value {
    ...
}

/// Returns the current (pre-populated) value for the active step, if any.
fn current_value(ws: &WizardState) -> Option<&str> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
