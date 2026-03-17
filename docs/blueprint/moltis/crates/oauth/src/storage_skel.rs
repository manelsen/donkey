use std::{collections::HashMap, path::PathBuf};

use tracing::{debug, info, warn};

use crate::{Result, config_dir::moltis_config_dir, types::OAuthTokens};

/// File-based token storage at `~/.config/moltis/oauth_tokens.json`.
#[derive(Debug, Clone)]
pub struct TokenStore {
    ...
}

impl TokenStore {
    pub fn new() -> Self {

    /// Create a token store at a specific path (useful for testing).
    pub fn with_path(path: PathBuf) -> Self {
    ...
}

    pub fn load(&self, provider: &str) -> Option<OAuthTokens> {
    ...
}

    pub fn save(&self, provider: &str, tokens: &OAuthTokens) -> Result<()> {
    ...
}

    pub fn delete(&self, provider: &str) -> Result<()> {
    ...
}

    pub fn list(&self) -> Vec<String> {
    ...
}
}

impl Default for TokenStore {
    fn default() -> Self {
}
