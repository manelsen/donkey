#![allow(clippy::unwrap_used, clippy::expect_used)]
//! Integration tests for the auth middleware protecting API endpoints.

use std::{
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use secrecy::ExposeSecret;

use tokio::net::TcpListener;
#[cfg(all(feature = "graphql", feature = "web-ui"))]
use tokio_tungstenite::{connect_async, tungstenite::client::IntoClientRequest};

use async_trait::async_trait;

use moltis_gateway::{
    auth::{self, CredentialStore},
    methods::MethodRegistry,
    server::{build_gateway_base, finalize_gateway_app},
    services::{GatewayServices, OnboardingService, ServiceResult},
    state::GatewayState,
};

/// Start a test server with a credential store (auth enabled).
async fn start_auth_server() -> (SocketAddr, Arc<CredentialStore>) {
    ...
}

/// Start a test server and also return the GatewayState for setup code tests.
async fn start_auth_server_with_state() -> (SocketAddr, Arc<CredentialStore>, Arc<GatewayState>) {
    ...
}

/// Start a localhost-only test server.
async fn start_localhost_server() -> (SocketAddr, Arc<CredentialStore>, Arc<GatewayState>) {
    ...
}

/// Start a test server that simulates being behind a proxy (all connections
/// treated as remote even though they originate from loopback).
async fn start_proxied_server() -> (SocketAddr, Arc<CredentialStore>, Arc<GatewayState>) {
    ...
}

async fn start_auth_server_impl(
    localhost_only: bool,
    behind_proxy: bool,
) -> (SocketAddr, Arc<CredentialStore>, Arc<GatewayState>) {
    ...
}

/// Start a localhost test server with a vault attached.
#[cfg(feature = "vault")]
async fn start_localhost_server_with_vault() -> (
    SocketAddr,
    Arc<CredentialStore>,
    Arc<GatewayState>,
    Arc<moltis_vault::Vault>,
) {
    ...
}

/// Start a test server without a credential store (no auth).
async fn start_noauth_server() -> SocketAddr {
    ...
}

/// When no credential store is configured, all API routes pass through.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn no_auth_configured_passes_through() {
    ...
}

/// When auth is configured but setup is not complete (no password set),
/// all API routes pass through.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_not_complete_passes_through() {
    ...
}

/// When auth is configured and setup is complete, unauthenticated requests
/// to protected endpoints return 401.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn unauthenticated_returns_401() {
    ...
}

/// Authenticated request with a valid session cookie succeeds.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn session_cookie_auth_succeeds() {
    ...
}

/// Authenticated request with a valid API key in Bearer header succeeds.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn api_key_auth_succeeds() {
    ...
}

/// Unauthenticated request to /api/images/cached returns 401 when auth is set up.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn images_endpoint_returns_401() {
    ...
}

/// Public routes remain accessible without auth even when auth is configured.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn public_routes_accessible_without_auth() {
    ...
}

/// GraphQL route is not public and requires authentication.
#[cfg(all(feature = "web-ui", feature = "graphql"))]
#[tokio::test]
async fn graphql_requires_auth_when_enabled() {
    ...
}

/// Runtime GraphQL toggle takes effect immediately without restart.
#[cfg(all(feature = "web-ui", feature = "graphql"))]
#[tokio::test]
async fn graphql_runtime_toggle_applies_immediately() {
    ...
}

/// GraphQL status query always returns an `uptimeMs` value.
#[cfg(all(feature = "web-ui", feature = "graphql"))]
#[tokio::test]
async fn graphql_status_includes_uptime_ms() {
    ...
}

/// GraphQL subscriptions upgrade on `/graphql` with GraphQL WS subprotocols.
#[cfg(all(feature = "web-ui", feature = "graphql"))]
#[tokio::test]
async fn graphql_websocket_upgrade_supported_on_graphql_path() {
    ...
}

/// Legacy `/graphql/ws` endpoint is not supported, subscriptions must use `/graphql`.
#[cfg(all(feature = "web-ui", feature = "graphql"))]
#[tokio::test]
async fn graphql_websocket_upgrade_not_supported_on_legacy_path() {
    ...
}

/// Invalid session cookie returns 401.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn invalid_session_cookie_returns_401() {
    ...
}

/// POST /api/auth/reset removes all auth and subsequent requests pass through.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn reset_auth_removes_all_authentication() {
    ...
}

/// After resetting auth then re-setting up, auth_disabled is cleared.
/// Reset generates a new setup code that must be provided.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn reenable_auth_after_reset() {
    ...
}

/// Reset without session returns 401.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn reset_auth_requires_session() {
    ...
}

/// Revoked API key returns 401.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn revoked_api_key_returns_401() {
    ...
}

// ── Setup code tests ─────────────────────────────────────────────────────────

/// Setup without code when code is required returns 403.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_without_code_when_required_returns_403() {
    ...
}

/// Setup with wrong code returns 403.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_with_wrong_code_returns_403() {
    ...
}

/// Setup with correct code succeeds.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_with_correct_code_succeeds() {
    ...
}

/// Setup code not required when already set up.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_code_not_required_when_already_setup() {
    ...
}

/// Status reports setup_code_required when code is set.
/// Uses a "proxied" server so the local connection is treated as remote
/// (otherwise the three-tier model auto-bypasses auth for local connections
/// without a password, making setup_required = false).
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn status_reports_setup_code_required() {
    ...
}

/// Setup code not required when auth is disabled.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_code_not_required_when_auth_disabled() {
    ...
}

// ── Localhost tests ──────────────────────────────────────────────────────────

/// On localhost with no password, status returns authenticated: true.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn localhost_no_password_status_authenticated() {
    ...
}

/// On localhost with no password, session-protected endpoints work (AuthSession bypass).
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn localhost_no_password_session_endpoints_accessible() {
    ...
}

/// On localhost with no password, can set a password via /api/auth/password/change.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn localhost_set_password_without_current() {
    ...
}

/// Unauthenticated POST to /api/sessions/:key/upload returns 401.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn upload_endpoint_requires_auth() {
    ...
}

/// Unauthenticated GET to /api/sessions/:key/media/:file returns 401.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn media_endpoint_requires_auth() {
    ...
}

/// On localhost with password set, status returns has_password: true.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn localhost_with_password_requires_login() {
    ...
}

/// On localhost with a passkey registered, unauthenticated requests require login.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn localhost_with_passkey_requires_login() {
    ...
}

/// When a new passkey host is detected after passkeys already exist, status
/// should expose a host-update warning for the UI banner.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn status_reports_passkey_host_update_warning() {
    ...
}

// ── Three-tier model tests ──────────────────────────────────────────────────

/// Tier 3: proxied server + no password → protected API returns 401.
/// Remote connections without a password can only reach /api/auth/* for setup.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn proxied_no_password_protected_returns_401() {
    ...
}

/// Tier 3: proxied server + no password → auth status is accessible (public route).
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn proxied_no_password_auth_status_accessible() {
    ...
}

/// Tier 1: proxied server + password set → always requires auth.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn proxied_with_password_requires_auth() {
    ...
}

// ── Cookie domain tests ─────────────────────────────────────────────────────

/// Login via /api/auth/login with a Host header containing a .localhost
/// subdomain (e.g. moltis.localhost) should set Domain=localhost on the
/// session cookie so the cookie is shared across all loopback hostnames.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn login_cookie_includes_domain_for_localhost_subdomain() {
    ...
}

/// Login with a plain localhost Host should also include Domain=localhost
/// so the cookie works for both localhost and moltis.localhost.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn login_cookie_includes_domain_for_plain_localhost() {
    ...
}

/// Login with an external Host header should NOT add a Domain attribute
/// to the cookie (host-only cookie, no domain sharing).
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn login_cookie_omits_domain_for_external_host() {
    ...
}

/// Password login attempts are throttled to reduce brute-force attempts.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn login_endpoint_rate_limited_after_repeated_failures() {
    ...
}

/// Normal API endpoints are also throttled with a higher ceiling for regular use.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn api_endpoint_rate_limited_after_high_request_volume() {
    ...
}

// ── Onboarding auth protection tests ─────────────────────────────────────────

/// During setup (no password), a local connection to /onboarding passes
/// through without redirect — the SPA handles onboarding routing itself.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn onboarding_passes_through_for_local_during_setup() {
    ...
}

/// During setup (no password), a remote connection to /onboarding also
/// passes through — the onboarding page handles its own auth via setup
/// codes (step 0).
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn onboarding_passes_through_for_remote_during_setup() {
    ...
}

/// During setup (no password), a remote connection to / is redirected to
/// /setup-required (same as /onboarding).
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn root_redirects_to_setup_required_for_remote() {
    ...
}

/// /setup-required is a public path and serves content even for remote
/// connections during setup (no redirect loop).
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_required_page_accessible_for_remote() {
    ...
}

/// After setup is complete, /setup-required redirects to /login so stale
/// bookmarks don't show a misleading "Authentication Not Configured" page.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_required_redirects_to_login_after_setup() {
    ...
}

/// After setup is complete, /onboarding requires authentication — an
/// unauthenticated remote request must be redirected to /login.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn onboarding_requires_auth_after_setup() {
    ...
}

/// After setup, an authenticated request to /onboarding is allowed through
/// (the onboarding handler itself decides whether to show the page or redirect
/// to /).
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn onboarding_accessible_with_session_after_setup() {
    ...
}

/// After auth is reset, `/onboarding` must stay reachable even if the
/// onboarding service still reports the instance as previously onboarded.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn onboarding_remains_accessible_after_auth_reset_when_onboarded() {
    ...
}

/// POST /api/auth/setup is rejected with 403 after setup is already complete.
/// This prevents an attacker from resetting the password via the setup endpoint.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn setup_endpoint_rejected_after_setup_complete() {
    ...
}

/// Authenticated requests bypass IP throttling.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn authenticated_api_endpoint_not_rate_limited() {
    ...
}

/// Setting a password via /api/auth/password/change on a localhost server with a
/// vault should initialize the vault and return a recovery key.
#[cfg(all(feature = "web-ui", feature = "vault"))]
#[tokio::test]
async fn password_change_initializes_vault() {
    ...
}

/// Setting a password via /api/auth/password/change when the vault is already
/// initialized should not return a recovery key (no double-init).
#[cfg(all(feature = "web-ui", feature = "vault"))]
#[tokio::test]
async fn password_change_on_initialized_vault_no_recovery_key() {
    ...
}

// ── Onboarding auth bypass tests ────────────────────────────────────────────

/// Mock onboarding service with controllable `onboarded` flag.
struct MockOnboardingService {
    ...
}

#[async_trait]
impl OnboardingService for MockOnboardingService {
    async fn wizard_start(&self, _p: serde_json::Value) -> ServiceResult {

    async fn wizard_next(&self, _p: serde_json::Value) -> ServiceResult {
    ...
}

    async fn wizard_cancel(&self) -> ServiceResult {
    ...
}

    async fn wizard_status(&self) -> ServiceResult {
    ...
}

    async fn identity_get(&self) -> ServiceResult {
    ...
}

    async fn identity_update(&self, _params: serde_json::Value) -> ServiceResult {
    ...
}

    async fn identity_update_soul(&self, _soul: Option<String>) -> ServiceResult {
    ...
}

    async fn openclaw_detect(&self) -> ServiceResult {
    ...
}

    async fn openclaw_scan(&self) -> ServiceResult {
    ...
}

    async fn openclaw_import(&self, _params: serde_json::Value) -> ServiceResult {
    ...
}
}

/// Start a test server with a mock onboarding service.
///
/// When `behind_proxy` is true, connections are treated as remote.
#[cfg(feature = "web-ui")]
async fn start_server_with_onboarding(
    onboarded: bool,
    behind_proxy: bool,
) -> (SocketAddr, Arc<CredentialStore>, Arc<GatewayState>) {
    ...
}

/// During onboarding (password set but onboarded=false), a local API request
/// bypasses auth and succeeds. This is the STT test button scenario.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn local_api_during_onboarding_bypasses_auth() {
    ...
}

/// After onboarding completes (onboarded=true), a local API request without
/// credentials must return 401 — the bypass is no longer active.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn local_api_after_onboarding_requires_auth() {
    ...
}

/// Remote API requests during onboarding must still require auth — the
/// bypass only applies to local connections.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn remote_api_during_onboarding_requires_auth() {
    ...
}

/// Privileged endpoints are NOT covered by the onboarding bypass, even for
/// local connections during onboarding. Only the narrow set of paths needed
/// by the wizard is allowed through.
#[cfg(feature = "web-ui")]
#[tokio::test]
async fn local_privileged_api_during_onboarding_requires_auth() {
    ...
}
