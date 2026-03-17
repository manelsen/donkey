//! HTTP routes for Tailscale Serve/Funnel management.

use {
    axum::{
        Json, Router,
        extract::State,
        http::StatusCode,
        response::IntoResponse,
        routing::{get, post},
    },
    serde::Deserialize,
    tracing::{debug, error, info, warn},
};

use crate::{
    server::AppState,
    tailscale::{CliTailscaleManager, TailscaleManager, TailscaleMode, validate_tailscale_config},
};

const TAILSCALE_STATUS_FAILED: &str = "TAILSCALE_STATUS_FAILED";
const TAILSCALE_MODE_INVALID: &str = "TAILSCALE_MODE_INVALID";
const TAILSCALE_CONFIG_INVALID: &str = "TAILSCALE_CONFIG_INVALID";
const TAILSCALE_CONFIGURE_FAILED: &str = "TAILSCALE_CONFIGURE_FAILED";

async fn sync_webauthn_host_and_notice(state: &AppState, hostname: Option<&str>) -> Option<String> {
    ...
}

fn tailscale_error(code: &str, error: impl Into<String>) -> serde_json::Value {
    ...
}

#[derive(Deserialize)]
struct ConfigureRequest {
    ...
}

/// Build the tailscale API router.
pub fn tailscale_router() -> Router<AppState> {
    ...
}

async fn status_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

async fn configure_handler(
    State(state): State<AppState>,
    Json(body): Json<ConfigureRequest>,
) -> impl IntoResponse {
    ...
}
