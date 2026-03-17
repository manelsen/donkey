//! Hook eligibility checks.
//!
//! Before loading a hook, validate its requirements against the current
//! system environment.

use crate::hook_metadata::HookMetadata;

/// Result of eligibility checks.
#[derive(Debug, Clone)]
pub struct EligibilityResult {
    ...
}

/// Check whether a hook's requirements are met on the current system.
pub fn check_hook_eligibility(metadata: &HookMetadata) -> EligibilityResult {
    ...
}

/// Check if a binary exists on PATH.
fn bin_exists(name: &str) -> bool {
    ...
}

#[cfg(test)]
mod tests {

    fn minimal_metadata() -> HookMetadata {
    ...
}

    #[test]
    fn no_requirements_is_eligible() {
    ...
}

    #[test]
    fn wrong_os_is_ineligible() {
    ...
}

    #[test]
    fn current_os_is_eligible() {
    ...
}

    #[test]
    fn missing_bin_is_ineligible() {
    ...
}

    #[test]
    fn missing_env_is_ineligible() {
    ...
}

    #[test]
    fn present_env_is_eligible() {
    ...
}
}
