//! HTTP request metrics middleware.
//!
//! This middleware collects Prometheus metrics for all HTTP requests passing through
//! the gateway. It tracks request counts, durations, and in-flight requests.

#[cfg(feature = "metrics")]
use std::time::Instant;

#[cfg(feature = "metrics")]
use axum::{body::Body, http::Request, middleware::Next, response::Response};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, gauge, histogram};

#[cfg(feature = "metrics")]
use moltis_metrics::{http as http_metrics, labels};

/// Middleware that collects HTTP request metrics.
///
/// This records:
/// - `moltis_http_requests_total`: Counter of total requests by endpoint, method, and status
/// - `moltis_http_request_duration_seconds`: Histogram of request durations
/// - `moltis_http_requests_in_flight`: Gauge of currently processing requests
#[cfg(feature = "metrics")]
pub async fn http_metrics_middleware(request: Request<Body>, next: Next) -> Response {
    ...
}

/// Normalize a URL path for metric labels.
///
/// This replaces dynamic segments (UUIDs, IDs) with placeholders to prevent
/// high cardinality in metric labels.
#[cfg(feature = "metrics")]
fn normalize_path(path: &str) -> String {
    ...
}

/// Check if a string looks like a UUID.
#[cfg(feature = "metrics")]
fn looks_like_uuid(s: &str) -> bool {
    ...
}

#[cfg(all(test, feature = "metrics"))]
mod tests {

    #[test]
    fn test_looks_like_uuid() {
    ...
}
}
