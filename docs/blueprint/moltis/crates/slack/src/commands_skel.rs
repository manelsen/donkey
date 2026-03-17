//! Slack slash command manifest generation.
//!
//! Slack does not support programmatic command registration (unlike Discord).
//! Commands must be configured in the Slack app manifest. This module
//! generates the manifest snippet that users paste into their Slack app config.

/// A slash command definition.
#[derive(Debug, Clone)]
pub struct SlackCommandDef {
    ...
}

/// Returns the list of channel control commands.
pub fn command_definitions() -> Vec<SlackCommandDef> {
    ...
}

/// Generate a Slack app manifest YAML snippet for slash commands.
///
/// The output should be pasted into the `features.slash_commands` section
/// of a Slack app manifest.
pub fn generate_manifest_snippet(request_url_base: &str) -> String {
    ...
}

/// Generate a JSON array of command definitions for API responses.
pub fn command_definitions_json() -> serde_json::Value {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn manifest_snippet_contains_commands() {
    ...
}

    #[test]
    fn command_definitions_json_structure() {
    ...
}
}
