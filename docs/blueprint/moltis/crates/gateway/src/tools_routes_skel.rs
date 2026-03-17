//! API routes for configuration editing.
//!
//! Provides endpoints to get, validate, and save the full moltis config as TOML.
//!
//! SECURITY: These endpoints expose sensitive configuration including API keys.
//! They are protected by auth middleware, but also have explicit checks to ensure
//! they never work without authentication on non-localhost connections.

use axum::{Json, extract::State, http::StatusCode, response::IntoResponse};

const CONFIG_AUTH_REQUIRED: &str = "CONFIG_AUTH_REQUIRED";
const CONFIG_READ_FAILED: &str = "CONFIG_READ_FAILED";
const CONFIG_TOML_REQUIRED: &str = "CONFIG_TOML_REQUIRED";
const CONFIG_INVALID_TOML: &str = "CONFIG_INVALID_TOML";
const CONFIG_SAVE_FAILED: &str = "CONFIG_SAVE_FAILED";
const CONFIG_RESTART_INVALID: &str = "CONFIG_RESTART_INVALID";
const CONFIG_RESTART_READ_FAILED: &str = "CONFIG_RESTART_READ_FAILED";

fn config_error(code: &str, error: impl Into<String>) -> serde_json::Value {
    ...
}

/// Check if the request should be allowed for config operations.
///
/// Config endpoints are ONLY allowed when:
/// - Running on localhost (loopback interface only), OR
/// - User is authenticated via session or API key
///
/// This is a defense-in-depth check on top of the auth middleware.
async fn require_config_access(state: &crate::server::AppState) -> Result<(), impl IntoResponse> {
    ...
}

/// Get the current configuration as TOML.
pub async fn config_get(State(state): State<crate::server::AppState>) -> impl IntoResponse {
    ...
}

/// Validate configuration TOML without saving.
pub async fn config_validate(
    State(state): State<crate::server::AppState>,
    Json(body): Json<serde_json::Value>,
) -> impl IntoResponse {
    ...
}

/// Get the default configuration template with all options documented.
/// Preserves the current port from the existing config.
pub async fn config_template(State(state): State<crate::server::AppState>) -> impl IntoResponse {
    ...
}

/// Save configuration from TOML.
pub async fn config_save(
    State(state): State<crate::server::AppState>,
    Json(body): Json<serde_json::Value>,
) -> impl IntoResponse {
    ...
}

/// Restart the moltis process.
///
/// This re-runs the current binary with the same arguments. On Unix, it uses the exec
/// syscall to replace the current process. On other platforms, it spawns a new process.
///
/// Before restarting, the saved config is loaded from disk and validated. If the config
/// is invalid the restart is refused so the server doesn't crash on startup.
pub async fn restart(State(state): State<crate::server::AppState>) -> impl IntoResponse {
    ...
}

/// Validate config and return warnings.
fn validate_config(config: &moltis_config::MoltisConfig) -> Vec<String> {
    ...
}
