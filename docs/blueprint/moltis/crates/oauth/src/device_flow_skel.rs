use {reqwest::header::HeaderMap, secrecy::Secret};

use crate::{
    Error, Result,
    types::{OAuthConfig, OAuthTokens},
};

/// Response from the device code request.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DeviceCodeResponse {
    ...
}

fn default_interval() -> u64 {
    ...
}

/// Request a device code from the provider.
pub async fn request_device_code(
    client: &reqwest::Client,
    config: &OAuthConfig,
) -> Result<DeviceCodeResponse> {
    ...
}

/// Request a device code, optionally sending extra headers.
pub async fn request_device_code_with_headers(
    client: &reqwest::Client,
    config: &OAuthConfig,
    extra_headers: Option<&HeaderMap>,
) -> Result<DeviceCodeResponse> {
    ...
}

#[derive(Debug, serde::Deserialize)]
struct TokenPollResponse {
    ...
}

/// Poll the token endpoint until the user completes the device flow.
pub async fn poll_for_token(
    client: &reqwest::Client,
    config: &OAuthConfig,
    device_code: &str,
    interval: u64,
) -> Result<OAuthTokens> {
    ...
}

/// Poll the token endpoint, optionally sending extra headers.
pub async fn poll_for_token_with_headers(
    client: &reqwest::Client,
    config: &OAuthConfig,
    device_code: &str,
    interval: u64,
    extra_headers: Option<&HeaderMap>,
) -> Result<OAuthTokens> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
