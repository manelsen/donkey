use std::time::{Duration, Instant};

use {
    anyhow::Result,
    secrecy::{ExposeSecret, Secret},
    serde::Deserialize,
};

use crate::config::MsTeamsAccountConfig;

#[derive(Clone)]
pub struct CachedAccessToken {
    ...
}

impl CachedAccessToken {
    fn is_valid(&self) -> bool {
}

#[derive(Debug, Deserialize)]
struct TokenResponse {
    ...
}

pub async fn get_access_token(
    client: &reqwest::Client,
    config: &MsTeamsAccountConfig,
    cache: &tokio::sync::Mutex<Option<CachedAccessToken>>,
) -> Result<Secret<String>> {
    ...
}
