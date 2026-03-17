//! Pure state machine for the onboarding wizard. No I/O.

use moltis_config::{AgentIdentity, UserProfile};

/// Steps in the onboarding wizard.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum WizardStep {
    ...
}

/// The wizard state, advanced one step at a time.
#[derive(Debug, Clone)]
pub struct WizardState {
    ...
}

impl Default for WizardState {
    fn default() -> Self {
}

impl WizardState {
    pub fn new() -> Self {

    /// The prompt text to display for the current step.
    pub fn prompt(&self) -> &str {
    ...
}

    /// Process user input and advance to the next step.
    pub fn advance(&mut self, input: &str) {
    ...
}

    pub fn is_done(&self) -> bool {
    ...
}
}

#[cfg(test)]
mod tests {

    #[test]
    fn back_from_confirm() {
    ...
}

    #[test]
    fn default_agent_name() {
    ...
}
}
