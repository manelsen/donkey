#![allow(clippy::unwrap_used, clippy::expect_used)]
use {
    mockito::Matcher,
    moltis_oauth::{
        OAuthConfig, OAuthFlow, TokenStore, callback_port, load_oauth_config, pkce::generate_pkce,
    },
    secrecy::{ExposeSecret, Secret},
};

#[test]
fn pkce_generates_valid_challenge() {
    ...
}

#[test]
fn pkce_is_deterministic_sha256() {
    ...
}

#[test]
fn load_oauth_config_returns_openai_codex_defaults() {
    ...
}

#[test]
fn load_oauth_config_returns_none_for_unknown() {
    ...
}

#[test]
fn callback_port_parses_from_redirect_uri() {
    ...
}

#[test]
fn oauth_flow_start_builds_valid_url() {
    ...
}

#[test]
fn oauth_flow_start_generates_unique_state() {
    ...
}

#[tokio::test]
async fn oauth_flow_exchange_sends_resource_indicator_when_configured() {
    ...
}

#[test]
fn token_store_roundtrip() {
    ...
}

// NOTE: env var override test is omitted because env vars are process-global
// and would interfere with parallel tests. The override logic is straightforward
// (std::env::var check in defaults.rs) and covered by code review.
