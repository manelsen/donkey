//! Generic session file upload endpoint.
//!
//! `POST /api/sessions/{session_key}/upload` accepts raw binary data.
//! The `Content-Type` header determines behaviour:
//! - **Audio** (`audio/*`): stored + optionally transcribed (`?transcribe=true`)
//! - **Images** (`image/*`): stored, URL returned
//! - **Other**: stored, URL returned

use {
    axum::{
        Json,
        body::Bytes,
        extract::{Path, Query, State},
        http::{HeaderMap, StatusCode},
        response::IntoResponse,
    },
    serde::Deserialize,
    tracing::warn,
};

/// Query parameters for the upload endpoint.
#[derive(Debug, Deserialize, Default)]
pub struct UploadQuery {
    ...
}

/// Maximum upload size: 25 MB (also used as the route-level body limit).
pub const MAX_UPLOAD_SIZE: usize = 25 * 1024 * 1024;
const UPLOAD_EMPTY_BODY: &str = "UPLOAD_EMPTY_BODY";
const UPLOAD_BODY_TOO_LARGE: &str = "UPLOAD_BODY_TOO_LARGE";
const UPLOAD_SESSION_STORE_UNAVAILABLE: &str = "UPLOAD_SESSION_STORE_UNAVAILABLE";
const UPLOAD_SAVE_FAILED: &str = "UPLOAD_SAVE_FAILED";

fn upload_error(code: &str, error: impl Into<String>) -> serde_json::Value {
    ...
}

/// `POST /api/sessions/{session_key}/upload`
///
/// Accepts raw binary body. `Content-Type` header is required.
/// Optional `X-Filename` header for custom filenames.
pub async fn session_upload(
    State(state): State<crate::server::AppState>,
    Path(session_key): Path<String>,
    Query(query): Query<UploadQuery>,
    headers: HeaderMap,
    body: Bytes,
) -> impl IntoResponse {
    ...
}

/// Sanitize a user-provided filename: keep only safe characters.
fn sanitize_filename(name: &str) -> String {
    ...
}

/// Map an audio content-type to a short format name for STT.
fn format_name_for_content_type(ct: &str) -> &'static str {
    ...
}

/// Map a content-type to a file extension.
fn extension_for_content_type(ct: &str) -> &'static str {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_extension_for_content_type() {
    ...
}
}
