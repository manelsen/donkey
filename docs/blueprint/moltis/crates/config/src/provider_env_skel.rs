use std::collections::HashMap;

use secrecy::Secret;

const PROVIDER_ENV_CANDIDATES: &[&str] = &["MOLTIS_PROVIDER", "PROVIDER"];
const API_KEY_ENV_CANDIDATES: &[&str] = &["MOLTIS_API_KEY", "API_KEY"];

#[derive(Clone)]
pub struct GenericProviderEnv {
    ...
}

fn non_empty_env_value(value: String) -> Option<String> {
    ...
}

fn env_value_from_source<F>(
    env_overrides: &HashMap<String, String>,
    key: &str,
    env_lookup: F,
) -> Option<String>
where
    F: FnOnce(&str) -> Option<String>,
{
    env_overrides
        .get(key)
        .cloned()
        .and_then(non_empty_env_value)
        .or_else(|| env_lookup(key).and_then(non_empty_env_value))
}

pub fn env_value_with_overrides(
    env_overrides: &HashMap<String, String>,
    key: &str,
) -> Option<String> {
    ...
}

/// Resolve the generic provider selector and API key from environment variables.
///
/// `MOLTIS_*` keys win over the bare aliases, but provider and API key are resolved
/// independently so mixed pairs such as `MOLTIS_PROVIDER` + `API_KEY` are accepted.
/// The concrete variable names used are returned for diagnostics and UI source labels.
pub fn generic_provider_env(env_overrides: &HashMap<String, String>) -> Option<GenericProviderEnv> {
    ...
}

pub fn generic_provider_api_key_from_env(
    provider: &str,
    env_overrides: &HashMap<String, String>,
) -> Option<Secret<String>> {
    ...
}

pub fn generic_provider_env_source_for_provider(
    provider: &str,
    env_overrides: &HashMap<String, String>,
) -> Option<String> {
    ...
}

pub fn normalize_provider_name(value: &str) -> Option<String> {
    ...
}

#[cfg(test)]
mod tests {
