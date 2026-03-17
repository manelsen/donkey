use {
    base64::{
        Engine,
        engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    },
    secrecy::Secret,
    url::Url,
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, oauth as oauth_metrics};

use crate::{
    Error, Result,
    pkce::{generate_pkce, generate_state},
    types::{OAuthConfig, OAuthTokens, PkceChallenge},
};

/// Manages the OAuth 2.0 authorization code flow with PKCE.
pub struct OAuthFlow {
    ...
}

/// Result of starting the OAuth flow.
pub struct AuthorizationRequest {
    ...
}

impl OAuthFlow {
    pub fn new(config: OAuthConfig) -> Self {

    /// Build the authorization URL and generate PKCE + state.
    pub fn start(&self) -> Result<AuthorizationRequest> {
    ...
}

    /// Exchange an authorization code for tokens.
    pub async fn exchange(&self, code: &str, verifier: &str) -> Result<OAuthTokens> {
    ...
}

    /// Refresh an access token using a refresh token.
    pub async fn refresh(&self, refresh_token: &str) -> Result<OAuthTokens> {
    ...
}
}

fn parse_token_response(resp: &serde_json::Value) -> Result<OAuthTokens> {
    ...
}

fn extract_account_id_from_tokens(access_token: &str, id_token: Option<&str>) -> Option<String> {
    ...
}

fn extract_account_id_from_jwt(token: &str) -> Option<String> {
    ...
}

fn parse_jwt_claims(token: &str) -> Option<serde_json::Value> {
    ...
}

fn extract_account_id_from_claims(claims: &serde_json::Value) -> Option<String> {
    ...
}
