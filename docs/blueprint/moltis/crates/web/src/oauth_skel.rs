//! OAuth callback handler.

use std::collections::HashMap;

use {
    axum::{
        extract::{Query, State},
        http::StatusCode,
        response::{Html, IntoResponse},
    },
    moltis_gateway::server::AppState,
};

pub async fn oauth_callback_handler(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    ...
}
