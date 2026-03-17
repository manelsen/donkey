//! SPA fallback, onboarding redirect, and login page handlers.

use {
    axum::{
        extract::State,
        http::{StatusCode, Uri},
        response::{IntoResponse, Redirect},
    },
    moltis_gateway::server::AppState,
};

use crate::templates::{
    SpaTemplate, onboarding_completed, render_spa_template, should_redirect_from_onboarding,
    should_redirect_to_onboarding,
};

pub async fn spa_fallback(State(state): State<AppState>, uri: Uri) -> impl IntoResponse {
    ...
}

pub async fn onboarding_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

pub async fn login_handler_page(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

pub async fn setup_required_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}
