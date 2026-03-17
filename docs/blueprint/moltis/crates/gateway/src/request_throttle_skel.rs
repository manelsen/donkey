use std::{
    net::{IpAddr, SocketAddr},
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use {
    axum::{
        extract::{ConnectInfo, State},
        http::{HeaderMap, Method, StatusCode},
        middleware::Next,
        response::{IntoResponse, Json, Response},
    },
    dashmap::{DashMap, mapref::entry::Entry},
};

use crate::server::AppState;

const CLEANUP_EVERY_REQUESTS: u64 = 512;
const RATE_LIMITED: &str = "RATE_LIMITED";

#[derive(Clone)]
pub struct RequestThrottle {
    ...
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum ThrottleScope {
    ...
}

impl ThrottleScope {
    fn from_request(method: &Method, path: &str) -> Option<Self> {
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct ThrottleKey {
    ...
}

#[derive(Debug, Clone, Copy)]
struct WindowState {
    ...
}

#[derive(Debug, Clone, Copy)]
struct RateLimit {
    ...
}

#[derive(Debug, Clone, Copy)]
struct ThrottleLimits {
    ...
}

impl Default for ThrottleLimits {
    fn default() -> Self {
}

enum ThrottleDecision {
    ...
}

impl RequestThrottle {
    #[must_use]
    pub fn new() -> Self {

    fn with_limits(limits: ThrottleLimits) -> Self {
    ...
}

    fn limit_for(&self, scope: ThrottleScope) -> RateLimit {
    ...
}

    fn check(&self, ip: IpAddr, scope: ThrottleScope) -> ThrottleDecision {
    ...
}

    fn check_at(&self, ip: IpAddr, scope: ThrottleScope, now: Instant) -> ThrottleDecision {
    ...
}

    fn cleanup_if_needed(&self, now: Instant) {
    ...
}

    fn max_window(&self) -> Duration {
    ...
}
}

impl Default for RequestThrottle {
    fn default() -> Self {
}

pub async fn throttle_gate(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    request: axum::http::Request<axum::body::Body>,
    next: Next,
) -> Response {
    ...
}

async fn should_bypass_throttling(state: &AppState, headers: &HeaderMap, addr: SocketAddr) -> bool {
    ...
}

fn rate_limited_response(path: String, retry_after: Duration) -> Response {
    ...
}

fn resolve_client_ip(headers: &HeaderMap, addr: SocketAddr, behind_proxy: bool) -> IpAddr {
    ...
}

fn extract_forwarded_ip(headers: &HeaderMap) -> Option<IpAddr> {
    ...
}

fn parse_ip(value: &str) -> Option<IpAddr> {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn classify_general_api_request() {
    ...
}

    #[test]
    fn classify_ws_request() {
    ...
}

    #[test]
    fn legacy_ws_root_path_is_not_classified() {
    ...
}

    #[test]
    fn classify_share_request() {
    ...
}

    #[test]
    fn login_window_limits_requests() {
    ...
}

    #[test]
    fn forwarded_ip_uses_first_xff_value() {
    ...
}
}
