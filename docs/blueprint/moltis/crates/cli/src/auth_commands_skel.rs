use {
    anyhow::Result,
    clap::Subcommand,
    moltis_oauth::{
        CallbackServer, OAuthFlow, TokenStore, callback_port, device_flow, load_oauth_config,
        parse_callback_input,
    },
};

#[derive(Subcommand)]
pub enum AuthAction {
    ...
}

pub async fn handle_auth(action: AuthAction) -> Result<()> {
    ...
}

async fn login(provider: &str) -> Result<()> {
    ...
}

fn read_pasted_callback_code(expected_state: &str) -> Result<String> {
    ...
}

fn extract_pasted_callback_code(input: &str, expected_state: &str) -> Result<String> {
    ...
}

async fn login_device_flow(provider: &str, config: &moltis_oauth::OAuthConfig) -> Result<()> {
    ...
}

/// Build provider-specific extra headers for the device flow.
fn build_provider_headers(provider: &str) -> Option<reqwest::header::HeaderMap> {
    ...
}

fn status() -> Result<()> {
    ...
}

fn logout(provider: &str) -> Result<()> {
    ...
}

fn reset_identity() -> Result<()> {
    ...
}

async fn reset_password() -> Result<()> {
    ...
}

fn reset_password_success_lines() -> [&'static str; 2] {
    ...
}

async fn create_api_key(label: &str, scopes_str: Option<String>) -> Result<()> {
    ...
}

#[cfg(test)]
mod tests {
