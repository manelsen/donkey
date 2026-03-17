use std::{net::SocketAddr, sync::Arc};

use secrecy::ExposeSecret;

use {
    axum::{
        Json,
        extract::{ConnectInfo, State},
        http::StatusCode,
        response::IntoResponse,
        routing::{delete, get, post},
    },
    axum_extra::extract::Host,
};

use crate::{
    auth::CredentialStore,
    auth_middleware::{AuthResult, AuthSession, SESSION_COOKIE, check_auth},
    auth_webauthn::WebAuthnRegistry,
    server::is_local_connection,
    state::GatewayState,
};

pub type SharedWebAuthnRegistry = Arc<tokio::sync::RwLock<WebAuthnRegistry>>;

/// Auth-related application state.
#[derive(Clone)]
pub struct AuthState {
    ...
}

impl axum::extract::FromRef<AuthState> for Arc<CredentialStore> {
    fn from_ref(state: &AuthState) -> Self {
}

impl axum::extract::FromRef<AuthState> for Arc<GatewayState> {
    fn from_ref(state: &AuthState) -> Self {
}

/// Build the auth router with all `/api/auth/*` routes.
pub fn auth_router() -> axum::Router<AuthState> {
    ...
}

/// Build vault-specific routes (no-op when vault feature is disabled).
#[cfg(feature = "vault")]
fn vault_routes() -> axum::Router<AuthState> {
    ...
}

#[cfg(not(feature = "vault"))]
fn vault_routes() -> axum::Router<AuthState> {
    ...
}

// ── Status ───────────────────────────────────────────────────────────────────

async fn status_handler(
    State(state): State<AuthState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: axum::http::HeaderMap,
) -> impl IntoResponse {
    ...
}

// ── Setup (first run) ────────────────────────────────────────────────────────

#[derive(serde::Deserialize)]
struct SetupRequest {
    ...
}

async fn setup_handler(
    State(state): State<AuthState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: axum::http::HeaderMap,
    Json(body): Json<SetupRequest>,
) -> impl IntoResponse {
    ...
}

// ── Login ────────────────────────────────────────────────────────────────────

#[derive(serde::Deserialize)]
struct LoginRequest {
    ...
}

async fn login_handler(
    State(state): State<AuthState>,
    headers: axum::http::HeaderMap,
    Json(body): Json<LoginRequest>,
) -> impl IntoResponse {
    ...
}

// ── Logout ───────────────────────────────────────────────────────────────────

async fn logout_handler(
    State(state): State<AuthState>,
    headers: axum::http::HeaderMap,
) -> impl IntoResponse {
    ...
}

// ── Reset all auth (requires session) ─────────────────────────────────────────

async fn reset_auth_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
    headers: axum::http::HeaderMap,
) -> impl IntoResponse {
    ...
}

// ── Password change (requires session) ───────────────────────────────────────

#[derive(serde::Deserialize)]
struct ChangePasswordRequest {
    ...
}

async fn change_password_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
    Json(body): Json<ChangePasswordRequest>,
) -> impl IntoResponse {
    ...
}

// ── API Keys (require session) ───────────────────────────────────────────────

async fn list_api_keys_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
) -> impl IntoResponse {
    ...
}

#[derive(serde::Deserialize)]
struct CreateApiKeyRequest {
    ...
}

async fn create_api_key_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
    Json(body): Json<CreateApiKeyRequest>,
) -> impl IntoResponse {
    ...
}

async fn revoke_api_key_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> impl IntoResponse {
    ...
}

// ── Passkeys (require session) ───────────────────────────────────────────────

async fn list_passkeys_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
) -> impl IntoResponse {
    ...
}

async fn remove_passkey_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> impl IntoResponse {
    ...
}

#[derive(serde::Deserialize)]
struct RenamePasskeyRequest {
    ...
}

async fn rename_passkey_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<RenamePasskeyRequest>,
) -> impl IntoResponse {
    ...
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Generate a random 6-digit numeric setup code.
pub fn generate_setup_code() -> String {
    ...
}

/// Build a session cookie string, adding `Domain=localhost` when the request
/// arrived on a `.localhost` subdomain (e.g. `moltis.localhost`) so the cookie
/// is shared across all loopback names per RFC 6761.
fn session_response(
    token: String,
    headers: &axum::http::HeaderMap,
    behind_proxy: bool,
) -> axum::response::Response {
    ...
}

fn clear_session_response(
    headers: &axum::http::HeaderMap,
    behind_proxy: bool,
) -> axum::response::Response {
    ...
}

/// Return `; Domain=localhost` when the request's `Host` header is a
/// `.localhost` subdomain (e.g. `moltis.localhost:8080`), otherwise `""`.
///
/// Without this, a session cookie set on `localhost` isn't sent by the browser
/// to `moltis.localhost` and vice versa because `Set-Cookie` without a `Domain`
/// attribute is a host-only cookie.  Adding `Domain=localhost` makes the
/// cookie available to `localhost` **and** all its subdomains (RFC 6265 §5.2.3).
fn localhost_cookie_domain(headers: &axum::http::HeaderMap, behind_proxy: bool) -> &'static str {
    ...
}

fn cookie_host(headers: &axum::http::HeaderMap, behind_proxy: bool) -> Option<&str> {
    ...
}
// ── Passkey registration (requires session) ──────────────────────────────────

async fn passkey_register_begin_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
    Host(host): Host,
) -> impl IntoResponse {
    ...
}

#[derive(serde::Deserialize)]
struct PasskeyRegisterFinishRequest {
    ...
}

async fn passkey_register_finish_handler(
    _session: AuthSession,
    State(state): State<AuthState>,
    Host(host): Host,
    Json(body): Json<PasskeyRegisterFinishRequest>,
) -> impl IntoResponse {
    ...
}

// ── Passkey authentication (no session required) ─────────────────────────────

async fn passkey_auth_begin_handler(
    State(state): State<AuthState>,
    Host(host): Host,
) -> impl IntoResponse {
    ...
}

#[derive(serde::Deserialize)]
struct PasskeyAuthFinishRequest {
    ...
}

async fn passkey_auth_finish_handler(
    State(state): State<AuthState>,
    Host(host): Host,
    headers: axum::http::HeaderMap,
    Json(body): Json<PasskeyAuthFinishRequest>,
) -> impl IntoResponse {
    ...
}

// ── Setup-time passkey registration (setup code instead of session) ───────────

#[derive(serde::Deserialize)]
struct SetupPasskeyBeginRequest {
    ...
}

async fn setup_passkey_register_begin_handler(
    State(state): State<AuthState>,
    Host(host): Host,
    Json(body): Json<SetupPasskeyBeginRequest>,
) -> impl IntoResponse {
    ...
}

#[derive(serde::Deserialize)]
struct SetupPasskeyFinishRequest {
    ...
}

async fn setup_passkey_register_finish_handler(
    State(state): State<AuthState>,
    Host(host): Host,
    headers: axum::http::HeaderMap,
    Json(body): Json<SetupPasskeyFinishRequest>,
) -> impl IntoResponse {
    ...
}

/// Look up the `WebAuthnState` matching the request hostname (`Host` or
/// `:authority`). Matching includes RP IDs and explicitly allowed origin hosts.
async fn host_to_webauthn(
    host: &str,
    registry: &SharedWebAuthnRegistry,
) -> Option<Arc<crate::auth_webauthn::WebAuthnState>> {
    ...
}

fn extract_session_token(headers: &axum::http::HeaderMap) -> Option<&str> {
    ...
}

// ── Vault handlers ──────────────────────────────────────────────────────────

#[cfg(feature = "vault")]
async fn vault_status_handler(State(state): State<AuthState>) -> impl IntoResponse {
    ...
}

#[cfg(feature = "vault")]
#[derive(serde::Deserialize)]
struct VaultUnlockRequest {
    ...
}

#[cfg(feature = "vault")]
async fn vault_unlock_handler(
    State(state): State<AuthState>,
    Json(body): Json<VaultUnlockRequest>,
) -> impl IntoResponse {
    ...
}

#[cfg(feature = "vault")]
#[derive(serde::Deserialize)]
struct VaultRecoveryRequest {
    ...
}

#[cfg(feature = "vault")]
async fn vault_recovery_handler(
    State(state): State<AuthState>,
    Json(body): Json<VaultRecoveryRequest>,
) -> impl IntoResponse {
    ...
}

/// Migrate unencrypted env vars to encrypted after vault unseal.
#[cfg(feature = "vault")]
async fn run_vault_env_migration(state: &AuthState) {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn localhost_cookie_domain_plain_localhost() {
    ...
}

    #[test]
    fn localhost_cookie_domain_moltis_subdomain() {
    ...
}

    #[test]
    fn localhost_cookie_domain_bare_localhost_no_port() {
    ...
}

    #[test]
    fn localhost_cookie_domain_external_host_omits_domain() {
    ...
}

    #[test]
    fn localhost_cookie_domain_tailscale_host_omits_domain() {
    ...
}

    #[test]
    fn localhost_cookie_domain_ip_address_omits_domain() {
    ...
}

    #[test]
    fn localhost_cookie_domain_no_host_header_omits_domain() {
    ...
}

    #[test]
    fn localhost_cookie_domain_proxy_mode_ignores_upstream_localhost_host() {
    ...
}

    #[test]
    fn localhost_cookie_domain_proxy_mode_uses_forwarded_host() {
    ...
}

    #[test]
    fn localhost_cookie_domain_proxy_mode_supports_forwarded_localhost_subdomain() {
    ...
}

    #[test]
    fn session_response_includes_domain_for_localhost() {
    ...
}

    #[test]
    fn session_response_omits_domain_for_external_host() {
    ...
}

    #[test]
    fn clear_session_response_includes_domain_for_localhost() {
    ...
}

    #[test]
    fn session_response_proxy_mode_omits_localhost_domain_without_forwarded_host() {
    ...
}
}
