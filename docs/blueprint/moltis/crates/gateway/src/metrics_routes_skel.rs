//! Metrics API routes for Prometheus scraping and internal UI.

#[cfg(feature = "metrics")]
use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Json},
};

#[cfg(feature = "prometheus")]
use axum::{http::header, response::Response};

#[cfg(feature = "metrics")]
use moltis_metrics::MetricsSnapshot;

#[cfg(feature = "metrics")]
use crate::server::AppState;

#[cfg(feature = "metrics")]
const METRICS_NOT_ENABLED: &str = "METRICS_NOT_ENABLED";

/// Prometheus metrics endpoint handler.
///
/// Returns metrics in Prometheus text exposition format, suitable for scraping
/// by Prometheus, Victoria Metrics, or other compatible collectors.
///
/// This endpoint is unauthenticated to allow metric scrapers to access it.
#[cfg(feature = "prometheus")]
pub async fn prometheus_metrics_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

/// Internal metrics API handler for the web UI.
///
/// Returns metrics as structured JSON, with pre-computed aggregates and
/// category breakdowns suitable for dashboard display.
#[cfg(feature = "metrics")]
pub async fn api_metrics_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

/// Metrics summary for the navigation badge.
///
/// Returns a minimal summary suitable for displaying in the UI navigation.
#[cfg(feature = "metrics")]
pub async fn api_metrics_summary_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

/// Historical metrics data for time-series charts.
///
/// Returns metrics snapshots (sampled every 30 seconds)
/// for rendering charts in the monitoring UI.
#[cfg(feature = "metrics")]
pub async fn api_metrics_history_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}
