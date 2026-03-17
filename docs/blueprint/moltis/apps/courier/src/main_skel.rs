use std::{fs::File, net::SocketAddr, sync::Arc};

use {
    a2::{
        DefaultNotificationBuilder, Endpoint, NotificationBuilder, NotificationOptions,
        client::ClientConfig,
        request::notification::{Priority, PushType},
    },
    anyhow::{Context, Result},
    axum::{
        Json, Router,
        extract::State,
        http::{HeaderMap, StatusCode},
        routing::{get, post},
    },
    clap::Parser,
    serde::{Deserialize, Serialize},
    sha2::{Digest, Sha256},
};

/// Privacy-preserving APNS push relay for Moltis gateways.
///
/// Holds a single Apple .p8 key and forwards opaque "wake up" silent
/// pushes on behalf of self-hosted gateways. The relay never sees
/// message text or metadata.
#[derive(Parser, Debug)]
#[command(version)]
struct Args {
    ...
}

struct AppState {
    ...
}

#[derive(Deserialize)]
struct PushRequest {
    ...
}

#[derive(Deserialize, Clone, Copy, Default)]
#[serde(rename_all = "lowercase")]
enum ApnsEnvironment {
    ...
}

#[derive(Serialize)]
struct PushResponse {
    ...
}

#[derive(Serialize)]
struct ErrorResponse {
    ...
}

#[tokio::main]
async fn main() -> Result<()> {
    ...
}

async fn handle_health() -> StatusCode {
    ...
}

/// Extract bearer token from Authorization header and validate against expected.
///
/// Uses SHA-256 hash comparison to avoid timing side-channels.
/// Returns `true` if no auth is configured (open relay) or if the token matches.
fn check_auth(expected: &Option<String>, headers: &HeaderMap) -> bool {
    ...
}

async fn handle_push(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(req): Json<PushRequest>,
) -> Result<Json<PushResponse>, (StatusCode, Json<ErrorResponse>)> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn parse_push_request_sandbox() {
    ...
}

    #[test]
    fn parse_push_request_missing_token() {
    ...
}

    #[test]
    fn error_response_serializes() {
    ...
}

    #[test]
    fn push_response_serializes() {
    ...
}

    #[test]
    fn apns_environment_default_is_production() {
    ...
}

    // ── Auth validation tests ───────────────────────────────────────────────

    #[test]
    fn check_auth_no_token_configured_accepts_all() {
    ...
}

    #[test]
    fn check_auth_valid_bearer_token() {
    ...
}

    #[test]
    fn check_auth_wrong_bearer_token() {
    ...
}

    #[test]
    fn check_auth_missing_authorization_header() {
    ...
}

    #[test]
    fn check_auth_non_bearer_scheme() {
    ...
}

    #[test]
    fn check_auth_empty_bearer_value() {
    ...
}

    #[test]
    fn check_auth_bearer_only_no_space() {
    ...
}
}
