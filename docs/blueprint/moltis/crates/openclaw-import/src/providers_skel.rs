//! Import LLM provider configuration from OpenClaw.
//!
//! Reads auth-profiles.json for API keys and openclaw.json for model selection,
//! then maps to the Moltis `provider_keys.json` format.

use std::{
    collections::{HashMap, HashSet},
    path::Path,
};

use {
    moltis_oauth::{OAuthTokens, TokenStore},
    secrecy::Secret,
    serde::{Deserialize, Serialize},
    tracing::debug,
};

use crate::{
    detect::{OpenClawDetection, resolve_agent_auth_profiles_path},
    report::{CategoryReport, ImportCategory, ImportStatus},
    types::{OpenClawAuthProfile, OpenClawAuthProfileStore, OpenClawConfig},
};

/// Moltis `provider_keys.json` entry (matches gateway `ProviderConfig`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MoltisProviderConfig {
    ...
}

/// Imported provider data ready to be written.
#[derive(Debug, Clone, Default)]
pub struct ImportedProviders {
    ...
}

/// Map an OpenClaw provider name to a Moltis provider name.
pub fn map_provider_name(oc_name: &str) -> String {
    ...
}

/// Parse an OpenClaw model reference like `"anthropic/claude-opus-4-6"`
/// into `(provider_name, model_id)`.
pub fn parse_model_ref(model_ref: &str) -> Option<(String, String)> {
    ...
}

/// Import provider configuration from an OpenClaw installation.
pub fn import_providers(detection: &OpenClawDetection) -> (CategoryReport, ImportedProviders) {
    ...
}

/// Write imported providers to a `provider_keys.json` file.
pub fn write_provider_keys(
    providers: &HashMap<String, MoltisProviderConfig>,
    dest: &Path,
) -> crate::error::Result<()> {
    ...
}

fn load_config(path: &Path) -> OpenClawConfig {
    ...
}

fn load_auth_profiles(path: &Path) -> Option<OpenClawAuthProfileStore> {
    ...
}

fn extract_api_key(profile: &OpenClawAuthProfile) -> Option<String> {
    ...
}

fn extract_oauth_tokens(profile: &OpenClawAuthProfile) -> Option<OAuthTokens> {
    ...
}

fn normalize_expiry(expires: Option<u64>) -> Option<u64> {
    ...
}

/// Write imported OAuth tokens to Moltis `oauth_tokens.json`.
pub fn write_oauth_tokens(tokens: &HashMap<String, OAuthTokens>) -> crate::error::Result<()> {
    ...
}

/// Write imported OAuth tokens to a specific `oauth_tokens.json` path.
pub fn write_oauth_tokens_to_path(
    tokens: &HashMap<String, OAuthTokens>,
    path: &Path,
) -> crate::error::Result<()> {
    ...
}

fn write_oauth_tokens_with_store(
    tokens: &HashMap<String, OAuthTokens>,
    store: &TokenStore,
) -> crate::error::Result<()> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn parse_model_ref_valid() {
    ...
}

    #[test]
    fn parse_model_ref_google_maps_to_gemini() {
    ...
}

    #[test]
    fn parse_model_ref_invalid() {
    ...
}

    #[test]
    fn map_provider_names() {
    ...
}

    #[test]
    fn import_with_auth_profiles() {
    ...
}

    #[test]
    fn write_provider_keys_creates_file() {
    ...
}

    #[test]
    fn write_provider_keys_merges_existing() {
    ...
}

    #[test]
    fn import_oauth_profile_alias_fields() {
    ...
}

    #[test]
    fn write_oauth_tokens_roundtrip() {
    ...
}
}
