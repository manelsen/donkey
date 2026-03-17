//! Push notification API routes.

use {
    crate::{
        push::{PushPayload, PushService, PushSubscription},
        server::AppState,
    },
    axum::{
        Json, Router,
        extract::{ConnectInfo, State},
        http::{HeaderMap, StatusCode},
        response::IntoResponse,
        routing::{get, post},
    },
    chrono::Utc,
    serde::{Deserialize, Serialize},
    std::{net::SocketAddr, sync::Arc},
};

/// Response with the VAPID public key.
#[derive(Serialize)]
struct VapidKeyResponse {
    ...
}

/// Request to subscribe to push notifications.
#[derive(Deserialize)]
pub struct SubscribeRequest {
    ...
}

#[derive(Deserialize)]
pub struct SubscriptionKeys {
    ...
}

/// Request to unsubscribe from push notifications.
#[derive(Deserialize)]
pub struct UnsubscribeRequest {
    ...
}

/// A subscription summary for display.
#[derive(Serialize)]
struct SubscriptionSummary {
    ...
}

/// Status response.
#[derive(Serialize)]
struct PushStatusResponse {
    ...
}

/// Get the VAPID public key for push subscription.
async fn vapid_key_handler(
    State(state): State<AppState>,
) -> Result<Json<VapidKeyResponse>, StatusCode> {
    ...
}

/// Extract the client IP from headers (for proxies) or connection info.
fn extract_client_ip(headers: &HeaderMap, conn_addr: SocketAddr) -> String {
    ...
}

/// Subscribe to push notifications.
async fn subscribe_handler(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(req): Json<SubscribeRequest>,
) -> Result<impl IntoResponse, StatusCode> {
    ...
}

/// Unsubscribe from push notifications.
async fn unsubscribe_handler(
    State(state): State<AppState>,
    Json(req): Json<UnsubscribeRequest>,
) -> Result<impl IntoResponse, StatusCode> {
    ...
}

/// Parse a user agent string into a friendly device name.
fn parse_device_name(user_agent: Option<&str>) -> String {
    ...
}

/// Get push notification status.
async fn status_handler(State(state): State<AppState>) -> Json<PushStatusResponse> {
    ...
}

/// Create the push notification router.
pub fn push_router() -> Router<AppState> {
    ...
}

/// Send a push notification to all subscribers.
pub async fn send_push_notification(
    push_service: &Arc<PushService>,
    title: &str,
    body: &str,
    url: Option<&str>,
    session_key: Option<&str>,
) -> anyhow::Result<usize> {
    ...
}
