use std::time::Instant;

use {dashmap::DashMap, webauthn_rs::prelude::*};

use crate::credential_store::CredentialStore;

/// Challenge TTL: 5 minutes.
const CHALLENGE_TTL_SECS: u64 = 300;

/// Pending registration challenge.
struct PendingRegistration {
    ...
}

/// Pending authentication challenge.
struct PendingAuthentication {
    ...
}

/// Normalize a host/authority value for WebAuthn host matching.
pub fn normalize_host(host: &str) -> String {
    ...
}

fn collect_allowed_hosts(rp_id: &str, state: &WebAuthnState) -> Vec<String> {
    ...
}

/// WebAuthn state manager. Wraps `webauthn-rs` and stores in-flight
/// challenges in a `DashMap` with TTL-based expiry.
pub struct WebAuthnState {
    ...
}

impl WebAuthnState {
    /// Create a new WebAuthn state.
    ///
    /// `rp_id` is typically the hostname (e.g. "localhost" or "moltis.example.com").
    /// `rp_origin` is the full origin URL (e.g. "https://localhost:18080").
    /// `extra_origins` are additional origins accepted during verification (e.g.
    /// `http://m4max.local:18080` when accessing via mDNS hostname).
    pub fn new(rp_id: &str, rp_origin: &Url, extra_origins: &[Url]) -> anyhow::Result<Self> {

    /// Begin passkey registration. Returns (challenge_id, creation_options_json).
    pub fn start_registration(
        &self,
        existing_passkeys: &[Passkey],
    ) -> anyhow::Result<(String, CreationChallengeResponse)> {
    ...
}

    /// Finish passkey registration. Returns the new Passkey credential.
    pub fn finish_registration(
        &self,
        challenge_id: &str,
        response: &RegisterPublicKeyCredential,
    ) -> anyhow::Result<Passkey> {
    ...
}

    /// Begin passkey authentication. Returns (challenge_id, request_options_json).
    pub fn start_authentication(
        &self,
        credentials: &[Passkey],
    ) -> anyhow::Result<(String, RequestChallengeResponse)> {
    ...
}

    /// Finish passkey authentication. Returns the authenticated result.
    pub fn finish_authentication(
        &self,
        challenge_id: &str,
        response: &PublicKeyCredential,
    ) -> anyhow::Result<AuthenticationResult> {
    ...
}

    /// Return all allowed WebAuthn origins as strings (primary + extras).
    ///
    /// Strips the trailing `/` that `Url::to_string()` appends for path-less
    /// URLs so the frontend can display clean `host:port` values.
    pub fn get_allowed_origins(&self) -> Vec<String> {
    ...
}

    fn cleanup_expired(&self) {
    ...
}
}

/// Registry of WebAuthn instances keyed by RP ID, allowing passkey
/// registration/authentication from multiple hostnames (e.g. `localhost`
/// and `m4max.local`).
pub struct WebAuthnRegistry {
    ...
}

struct WebAuthnEntry {
    ...
}

impl Default for WebAuthnRegistry {
    fn default() -> Self {
}

impl WebAuthnRegistry {
    /// Create an empty registry.
    pub fn new() -> Self {

    /// Add a WebAuthn instance for the given RP ID.
    pub fn add(&mut self, rp_id: String, state: WebAuthnState) {
    ...
}

    /// Check whether the registry already contains the given RP ID.
    pub fn contains_rp_id(&self, rp_id: &str) -> bool {
    ...
}

    /// Check whether the registry already accepts the given hostname.
    pub fn contains_host(&self, host: &str) -> bool {
    ...
}

    /// Look up the `WebAuthnState` whose RP ID or allowed hostnames include
    /// the hostname portion of the request's `Host` header.
    pub fn get_for_host(&self, host: &str) -> Option<std::sync::Arc<WebAuthnState>> {
    ...
}

    /// Return combined allowed origins from all registered instances.
    pub fn get_all_origins(&self) -> Vec<String> {
    ...
}
}

/// Load all stored passkeys from the credential store as `webauthn_rs::Passkey` objects.
pub async fn load_passkeys(store: &CredentialStore) -> anyhow::Result<Vec<Passkey>> {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn registry_matches_extra_origin_host() {
    ...
}
}
