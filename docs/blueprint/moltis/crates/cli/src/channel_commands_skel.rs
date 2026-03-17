//! CLI subcommands for channel configuration.

use std::io::Write;

use {
    anyhow::{Result, anyhow},
    clap::{Args, Subcommand},
    rand::RngCore,
    serde_json::{Map, Value},
};

const DEFAULT_OAUTH_TENANT: &str = "botframework.com";
const DEFAULT_OAUTH_SCOPE: &str = "https://api.botframework.com/.default";

#[derive(Subcommand)]
pub enum ChannelAction {
    ...
}

#[derive(Subcommand)]
pub enum TeamsAction {
    ...
}

#[derive(Args, Clone)]
pub struct TeamsBootstrapArgs {
    ...
}

pub async fn handle_channels(action: ChannelAction) -> Result<()> {
    ...
}

fn handle_teams(action: TeamsAction) -> Result<()> {
    ...
}

fn run_teams_bootstrap(args: TeamsBootstrapArgs) -> Result<()> {
    ...
}

fn required_value(
    provided: Option<String>,
    prompt: &str,
    placeholder: Option<&str>,
) -> Result<String> {
    ...
}

fn prompt_required(prompt: &str, default: Option<&str>) -> Result<String> {
    ...
}

fn prompt_yes_no(prompt: &str, default_yes: bool) -> Result<bool> {
    ...
}

fn build_channel_config(
    app_id: &str,
    app_password: &str,
    oauth_tenant: &str,
    oauth_scope: &str,
    webhook_secret: &str,
    existing: Option<&Value>,
) -> Value {
    ...
}

fn default_gateway_base_url(config: &moltis_config::MoltisConfig) -> String {
    ...
}

fn validate_account_id(account_id: &str) -> Result<()> {
    ...
}

fn normalize_base_url(raw: &str) -> Result<String> {
    ...
}

fn build_webhook_endpoint(
    base_url: &str,
    account_id: &str,
    webhook_secret: &str,
) -> Result<String> {
    ...
}

fn generate_webhook_secret() -> String {
    ...
}

fn encode_query_component(value: &str) -> String {
    ...
}

fn hex_upper(value: u8) -> char {
    ...
}

fn print_setup_links() {
    ...
}

fn open_setup_links() {
    ...
}

#[allow(clippy::expect_used, clippy::unwrap_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn normalize_base_url_rejects_query() {
    ...
}

    #[test]
    fn account_id_validation_rejects_invalid_chars() {
    ...
}

    #[test]
    fn webhook_endpoint_encodes_secret() {
    ...
}

    #[test]
    fn generated_webhook_secret_has_expected_shape() {
    ...
}
}
