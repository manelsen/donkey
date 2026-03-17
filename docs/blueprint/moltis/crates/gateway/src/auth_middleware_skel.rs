use std::{net::SocketAddr, sync::Arc};

use axum::{
    extract::{ConnectInfo, FromRef, FromRequestParts},
    http::{HeaderMap, StatusCode, request::Parts},
};

#[cfg(any(feature = "web-ui", feature = "vault"))]
use axum::{
    extract::State,
    middleware::Next,
    response::{IntoResponse, Json, Redirect},
};
#[cfg(feature = "web-ui")]
use tracing::{debug, warn};

use crate::{
    auth::{AuthIdentity, AuthMethod, CredentialStore},
    server::is_local_connection,
    state::GatewayState,
};

/// Session cookie name.
pub const SESSION_COOKIE: &str = "moltis_session";
const AUTH_SETUP_REQUIRED: &str = "AUTH_SETUP_REQUIRED";
const AUTH_NOT_AUTHENTICATED: &str = "AUTH_NOT_AUTHENTICATED";

// ── AuthResult — single source of truth for auth decisions ──────────────────

/// Outcome of an auth check against a credential store.
#[derive(Debug, Clone)]
pub enum AuthResult {
    ...
}

/// Single source of truth for auth decisions.
///
/// Every code path that needs to decide "is this request authenticated?" must
/// call this function instead of reimplementing the logic. This prevents the
/// split-brain bugs that arise when `is_setup_complete()` and `has_password()`
/// diverge (e.g. passkey-only setups).
pub async fn check_auth(
    store: &CredentialStore,
    headers: &HeaderMap,
    is_local: bool,
) -> AuthResult {
    ...
}

// ── auth_gate — covers the entire router ────────────────────────────────────

/// Middleware that applies auth to **all** routes.
///
/// Public paths (assets, auth endpoints, health, etc.) are allowed through
/// without authentication. Everything else goes through [`check_auth()`].
#[cfg(feature = "web-ui")]
pub async fn auth_gate(
    State(state): State<super::server::AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    mut request: axum::http::Request<axum::body::Body>,
    next: Next,
) -> axum::response::Response {
    ...
}

/// Paths that never require authentication.
#[cfg(feature = "web-ui")]
fn is_public_path(path: &str) -> bool {
    ...
}

/// Paths eligible for the onboarding auth bypass (local + not-yet-onboarded).
///
/// Kept narrow so that privileged endpoints like `/api/config` or
/// `/api/restart` are never reachable without credentials.
#[cfg(feature = "web-ui")]
fn is_onboarding_bypass_path(path: &str) -> bool {
    ...
}

// ── Vault guard ─────────────────────────────────────────────────────────────

/// Middleware that blocks API requests when the vault is sealed.
///
/// Returns 423 Locked for API endpoints (except auth and gon) when the vault
/// is in `Sealed` state. `Uninitialized` is not blocked — the vault doesn't
/// exist yet and there's nothing to protect.
#[cfg(feature = "vault")]
pub async fn vault_guard(
    State(state): State<super::server::AppState>,
    request: axum::http::Request<axum::body::Body>,
    next: Next,
) -> axum::response::Response {
    ...
}

// ── AuthSession extractor ───────────────────────────────────────────────────

/// Axum extractor that validates the session cookie and produces an
/// `AuthIdentity`. Returns 401 if the session is missing or invalid.
///
/// When `auth_gate` has already run, it reads the [`AuthIdentity`] the
/// middleware inserted into extensions. For auth routes (on the public
/// allowlist, where `auth_gate` skips auth), it falls back to validating
/// the session cookie directly.
pub struct AuthSession(pub AuthIdentity);

impl<S> FromRequestParts<S> for AuthSession
where
    S: Send + Sync,
    Arc<CredentialStore>: FromRef<S>,
    Arc<GatewayState>: FromRef<S>,
{
    type Rejection = (StatusCode, &'static str);

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
    ...
}
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Extract the Cookie header value.
fn cookie_header(headers: &HeaderMap) -> Option<&str> {
    ...
}

/// Extract a Bearer token from the Authorization header.
fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    ...
}

/// Parse a specific cookie value from a Cookie header string.
pub fn parse_cookie<'a>(header: &'a str, name: &str) -> Option<&'a str> {
    for part in header.split(';') {
        let part = part.trim();
        if let Some(value) = part.strip_prefix(name)
            && let Some(value) = value.strip_prefix('=')
        {
            return Some(value);
        }
    }
    None
}

#[cfg(test)]
mod tests {

    #[cfg(feature = "web-ui")]
    #[test]
    fn terminal_ws_path_is_not_public() {
    ...
}

    #[cfg(feature = "web-ui")]
    #[test]
    fn chat_ws_path_is_not_public() {
    ...
}

    #[cfg(feature = "web-ui")]
    #[test]
    fn graphql_paths_are_not_public() {
    ...
}

    #[cfg(feature = "web-ui")]
    #[test]
    fn public_identity_path_is_public() {
    ...
}
}
