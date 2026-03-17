use {
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
};

/// OAuth 2.0 provider configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthConfig {
    ...
}

/// Stored OAuth tokens.
#[derive(Clone, Serialize, Deserialize)]
pub struct OAuthTokens {
    ...
}

impl std::fmt::Debug for OAuthTokens {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// PKCE challenge pair.
#[derive(Debug, Clone)]
pub struct PkceChallenge {
    ...
}

// ── Serde helpers for Secret<String> ────────────────────────────────────────

/// Serialize a `Secret<String>` by exposing its inner value.
/// Use only for fields that must round-trip through storage (config files, token JSON).
pub fn serialize_secret<S: serde::Serializer>(
    secret: &Secret<String>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(secret.expose_secret())
}

/// Serialize an `Option<Secret<String>>` by exposing its inner value.
pub fn serialize_option_secret<S: serde::Serializer>(
    secret: &Option<Secret<String>>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    match secret {
        Some(s) => serializer.serialize_some(s.expose_secret()),
        None => serializer.serialize_none(),
    }
}
