use std::collections::HashMap;

use crate::{config_dir::moltis_config_dir, types::OAuthConfig};

/// Default OAuth configurations for known providers.
fn builtin_defaults() -> HashMap<String, OAuthConfig> {
    ...
}

/// Path to the OAuth providers config file.
fn config_path() -> std::path::PathBuf {
    ...
}

/// Load the OAuth config for a provider.
///
/// Priority:
/// 1. User config file (`~/.config/moltis/oauth_providers.json`)
/// 2. Environment variables (`MOLTIS_OAUTH_{PROVIDER}_CLIENT_ID`, etc.)
/// 3. Built-in defaults
pub fn load_oauth_config(provider: &str) -> Option<OAuthConfig> {
    ...
}

/// The callback port for a provider config (parsed from redirect_uri).
pub fn callback_port(config: &OAuthConfig) -> u16 {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn load_openai_codex_config() {
    ...
}

    #[test]
    fn load_kimi_code_config() {
    ...
}

    #[test]
    fn load_unknown_provider_returns_none() {
    ...
}

    #[test]
    fn callback_port_empty_redirect_uri() {
    ...
}

    #[test]
    fn callback_port_with_redirect_uri() {
    ...
}
}
