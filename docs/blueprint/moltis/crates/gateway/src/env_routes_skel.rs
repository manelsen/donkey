use {
    axum::{
        Json,
        extract::{Path, State},
        http::StatusCode,
        response::{IntoResponse, Response},
    },
    serde::Serialize,
};

use crate::auth::EnvVarEntry;

// ── Typed responses ──────────────────────────────────────────────────────────

const ENV_STORE_UNAVAILABLE: &str = "ENV_STORE_UNAVAILABLE";
const ENV_KEY_REQUIRED: &str = "ENV_KEY_REQUIRED";
const ENV_KEY_INVALID: &str = "ENV_KEY_INVALID";
const ENV_LIST_FAILED: &str = "ENV_LIST_FAILED";
const ENV_SET_FAILED: &str = "ENV_SET_FAILED";
const ENV_DELETE_FAILED: &str = "ENV_DELETE_FAILED";

/// Successful mutation response (`{"ok": true}`).
#[derive(Serialize)]
pub struct OkResponse {
    ...
}

impl OkResponse {
    const fn success() -> Self {
}

impl IntoResponse for OkResponse {
    fn into_response(self) -> Response {
}

/// JSON error with an HTTP status code.
pub struct ApiError {
    ...
}

impl ApiError {
    fn service_unavailable(code: &'static str, msg: &str) -> Self {

    fn bad_request(code: &'static str, msg: &str) -> Self {
    ...
}

    fn internal(code: &'static str, err: impl std::fmt::Display) -> Self {
    ...
}
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        #[derive(Serialize)]
}

/// Env var listing response (`{"env_vars": [...]}`).
#[derive(Serialize)]
pub struct EnvListResponse {
    ...
}

impl IntoResponse for EnvListResponse {
    fn into_response(self) -> Response {
}

// ── Route handlers ───────────────────────────────────────────────────────────

/// List all environment variables (names only, no values).
pub async fn env_list(
    State(state): State<crate::server::AppState>,
) -> Result<EnvListResponse, ApiError> {
    ...
}

/// Set (upsert) an environment variable.
pub async fn env_set(
    State(state): State<crate::server::AppState>,
    Json(body): Json<serde_json::Value>,
) -> Result<OkResponse, ApiError> {
    ...
}

/// Delete an environment variable by id.
pub async fn env_delete(
    State(state): State<crate::server::AppState>,
    Path(id): Path<i64>,
) -> Result<OkResponse, ApiError> {
    ...
}

#[cfg(test)]
mod tests {
