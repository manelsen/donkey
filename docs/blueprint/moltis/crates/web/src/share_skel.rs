//! Share page and social image handlers.

use {
    axum::{
        extract::{Path, Query, State},
        http::StatusCode,
        response::{Html, IntoResponse},
    },
    axum_extra::extract::{
        CookieJar,
        cookie::{Cookie, SameSite},
    },
    moltis_gateway::server::AppState,
    tracing::warn,
};

use crate::templates::ShareAccessQuery;

fn not_found_share_response() -> axum::response::Response {
    ...
}

fn share_cookie_name(share_id: &str) -> String {
    ...
}

fn request_origin(headers: &axum::http::HeaderMap, tls_active: bool) -> Option<String> {
    ...
}

fn share_social_image_url(
    headers: &axum::http::HeaderMap,
    tls_active: bool,
    share_id: &str,
) -> String {
    ...
}

pub async fn share_page_handler(
    Path(share_id): Path<String>,
    Query(query): Query<ShareAccessQuery>,
    jar: CookieJar,
    State(state): State<AppState>,
    headers: axum::http::HeaderMap,
) -> axum::response::Response {
    ...
}

fn serve_static_share_html(body: String) -> axum::response::Response {
    ...
}

pub async fn share_social_image_handler(
    Path(share_id): Path<String>,
    Query(query): Query<ShareAccessQuery>,
    jar: CookieJar,
    State(state): State<AppState>,
) -> axum::response::Response {
    ...
}

fn serve_static_share_svg(svg: String) -> axum::response::Response {
    ...
}
