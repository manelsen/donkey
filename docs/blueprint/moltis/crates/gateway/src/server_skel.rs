use std::{
    collections::{HashMap, HashSet},
    fs::OpenOptions,
    io::Write,
    net::SocketAddr,
    path::{Path as FsPath, PathBuf},
    sync::Arc,
};

use secrecy::{ExposeSecret, Secret};

use {
    axum::{
        Router,
        extract::{ConnectInfo, State, WebSocketUpgrade},
        http::StatusCode,
        response::{IntoResponse, Json},
        routing::get,
    },
    tower_http::{
        catch_panic::CatchPanicLayer,
        compression::CompressionLayer,
        cors::{AllowOrigin, Any, CorsLayer},
        request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer},
        sensitive_headers::SetSensitiveHeadersLayer,
        set_header::SetResponseHeaderLayer,
        trace::{DefaultOnRequest, DefaultOnResponse, TraceLayer},
    },
    tracing::{Level, debug, info, warn},
};

use {moltis_channels::ChannelPlugin, moltis_protocol::TICK_INTERVAL_MS};

use moltis_providers::ProviderRegistry;

use moltis_tools::{
    approval::{ApprovalManager, ApprovalMode, SecurityLevel},
    exec::EnvVarProvider,
    sessions_communicate::{
        SendToSessionFn, SendToSessionRequest, SessionsHistoryTool, SessionsListTool,
        SessionsSendTool,
    },
    sessions_manage::{
        CreateSessionFn, CreateSessionRequest, DeleteSessionFn, DeleteSessionRequest,
        SessionsCreateTool, SessionsDeleteTool,
    },
};

use {
    moltis_projects::ProjectStore,
    moltis_sessions::{
        metadata::{SessionMetadata, SqliteSessionMetadata},
        session_events::{SessionEvent, SessionEventBus},
        store::SessionStore,
    },
};

use crate::{
    approval::{GatewayApprovalBroadcaster, LiveExecApprovalService},
    auth,
    auth_routes::{AuthState, SharedWebAuthnRegistry, auth_router},
    broadcast::{BroadcastOpts, broadcast, broadcast_tick},
    chat::{LiveChatService, LiveModelService},
    methods::MethodRegistry,
    provider_setup::LiveProviderSetupService,
    services::GatewayServices,
    session::LiveSessionService,
    state::GatewayState,
    update_check::{UPDATE_CHECK_INTERVAL, fetch_update_availability, resolve_releases_url},
    ws::handle_connection,
};

#[cfg(feature = "tailscale")]
use crate::tailscale::{
    CliTailscaleManager, TailscaleManager, TailscaleMode, validate_tailscale_config,
};

#[cfg(feature = "tls")]
use crate::tls::CertManager;

/// Options for tailscale serve/funnel passed from CLI flags.
#[cfg(feature = "tailscale")]
pub struct TailscaleOpts {
    ...
}

// ── Location requester ───────────────────────────────────────────────────────

/// Gateway implementation of [`moltis_tools::location::LocationRequester`].
///
/// Uses the `PendingInvoke` + oneshot pattern to request the user's browser
/// geolocation and waits for `location.result` RPC to resolve it.
struct GatewayLocationRequester {
    ...
}

#[async_trait::async_trait]
impl moltis_tools::location::LocationRequester for GatewayLocationRequester {
    async fn request_location(
        &self,
        conn_id: &str,
        precision: moltis_tools::location::LocationPrecision,
    ) -> moltis_tools::Result<moltis_tools::location::LocationResult> {

    fn cached_location(&self) -> Option<moltis_config::GeoLocation> {
    ...
}

    async fn request_channel_location(
        &self,
        session_key: &str,
    ) -> moltis_tools::Result<moltis_tools::location::LocationResult> {
    ...
}
}

fn should_prebuild_sandbox_image(
    mode: &moltis_tools::sandbox::SandboxMode,
    packages: &[String],
) -> bool {
    ...
}

fn instance_slug(config: &moltis_config::MoltisConfig) -> String {
    ...
}

fn sandbox_container_prefix(instance_slug: &str) -> String {
    ...
}

fn browser_container_prefix(instance_slug: &str) -> String {
    ...
}

fn env_value_with_overrides(env_overrides: &HashMap<String, String>, key: &str) -> Option<String> {
    ...
}

fn merge_env_overrides(
    base_overrides: &HashMap<String, String>,
    additional: Vec<(String, String)>,
) -> HashMap<String, String> {
    ...
}

fn summarize_model_ids_for_logs(sorted_model_ids: &[String], max_items: usize) -> Vec<String> {
    ...
}

fn log_startup_model_inventory(reg: &ProviderRegistry) {
    ...
}

async fn ollama_has_model(base_url: &str, model: &str) -> bool {
    ...
}

async fn ensure_ollama_model(base_url: &str, model: &str) {
    ...
}

fn approval_manager_from_config(config: &moltis_config::MoltisConfig) -> ApprovalManager {
    ...
}

// ── Shared app state ─────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct AppState {
    ...
}

/// Function signature for adding extra routes (e.g. web-UI) to the gateway.
pub type RouteEnhancer = fn() -> Router<AppState>;

// ── Server startup ───────────────────────────────────────────────────────────

/// Build the API routes (shared between both build_gateway_app versions).
///
/// Auth is enforced by `auth_gate` middleware on the whole router — these
/// routes no longer carry their own auth layer.
/// Add feature-specific routes to API routes.
/// Build the CORS layer with dynamic host-based origin validation.
///
/// Instead of `allow_origin(Any)`, this validates the `Origin` header against the
/// request's `Host` header using the same `is_same_origin` logic as the WebSocket
/// CSWSH protection. This is secure for Docker/cloud deployments where the hostname
/// is unknown at build time — the server dynamically allows its own origin at
/// request time.
fn build_cors_layer() -> CorsLayer {
    ...
}

/// 2 MiB global request body limit — sufficient for any JSON API payload, small
/// enough to limit abuse. The upload endpoint has its own 25 MiB limit.
const REQUEST_BODY_LIMIT: usize = 2 * 1024 * 1024;

/// Apply the full middleware stack to the router.
///
/// Layer order (outermost → innermost for requests):
/// 1. `CatchPanicLayer` — converts handler panics to 500s
/// 2. `SetSensitiveHeadersLayer` — marks Authorization/Cookie as redacted
/// 3. `SetRequestIdLayer` — generates x-request-id before tracing
/// 4. `TraceLayer` (optional) — logs requests with redacted headers + request ID
/// 5. `CorsLayer` — handles preflight; logged by trace
/// 6. `PropagateRequestIdLayer` — copies x-request-id to response
/// 7. Security response headers — X-Content-Type-Options, X-Frame-Options, etc.
/// 8. `RequestBodyLimitLayer` — rejects oversized bodies
/// 9. `CompressionLayer` (innermost) — compresses response body
fn apply_middleware_stack<S>(
    router: Router<S>,
    cors: CorsLayer,
    http_request_logs: bool,
) -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    use axum::http::{HeaderValue, header};

    // Inner layers: compression, body limit, security headers, request ID propagation.
    let router = router
        .layer(CompressionLayer::new())
        .layer(tower_http::limit::RequestBodyLimitLayer::new(
            REQUEST_BODY_LIMIT,
        ))
        .layer(SetResponseHeaderLayer::overriding(
            header::HeaderName::from_static("x-content-type-options"),
            HeaderValue::from_static("nosniff"),
        ))
        .layer(SetResponseHeaderLayer::overriding(
            header::HeaderName::from_static("x-frame-options"),
            HeaderValue::from_static("sameorigin"),
        ))
        .layer(SetResponseHeaderLayer::overriding(
            header::HeaderName::from_static("referrer-policy"),
            HeaderValue::from_static("strict-origin-when-cross-origin"),
        ))
        .layer(PropagateRequestIdLayer::x_request_id())
        .layer(cors);

    // Optional trace layer — sees redacted headers and request ID.
    let router = apply_http_trace_layer(router, http_request_logs);

    // Outer layers: request ID generation, sensitive header marking, panic catching.
    router
        .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid))
        .layer(SetSensitiveHeadersLayer::new([
            header::AUTHORIZATION,
            header::COOKIE,
            header::SET_COOKIE,
        ]))
        .layer(CatchPanicLayer::new())
}

/// Apply optional HTTP request/response tracing layer.
fn apply_http_trace_layer<S>(router: Router<S>, enabled: bool) -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    if enabled {
        let http_trace = TraceLayer::new_for_http()
            .make_span_with(|request: &axum::http::Request<_>| {
                let request_id = request
                    .headers()
                    .get("x-request-id")
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("-")
                    .to_owned();
                let user_agent = request
                    .headers()
                    .get(axum::http::header::USER_AGENT)
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("-")
                    .to_owned();
                let referer = request
                    .headers()
                    .get(axum::http::header::REFERER)
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("-")
                    .to_owned();
                tracing::info_span!(
                    "http_request",
                    method = %request.method(),
                    uri = %request.uri(),
                    request_id = %request_id,
                    user_agent = %user_agent,
                    referer = %referer
                )
            })
            .on_request(DefaultOnRequest::new().level(Level::INFO))
            .on_response(DefaultOnResponse::new().level(Level::INFO));
        router.layer(http_trace)
    } else {
        router
    }
}

/// Build the gateway base router and `AppState` without throttle, middleware,
/// or state consumption. Callers can merge additional routes (e.g. web-UI)
/// before calling [`finalize_gateway_app`].
#[cfg(feature = "push-notifications")]
pub fn build_gateway_base(
    state: Arc<GatewayState>,
    methods: Arc<MethodRegistry>,
    push_service: Option<Arc<crate::push::PushService>>,
    webauthn_registry: Option<SharedWebAuthnRegistry>,
) -> (Router<AppState>, AppState) {
    ...
}

/// Build the gateway base router and `AppState` without throttle, middleware,
/// or state consumption. Callers can merge additional routes (e.g. web-UI)
/// before calling [`finalize_gateway_app`].
#[cfg(not(feature = "push-notifications"))]
pub fn build_gateway_base(
    state: Arc<GatewayState>,
    methods: Arc<MethodRegistry>,
    webauthn_registry: Option<SharedWebAuthnRegistry>,
) -> (Router<AppState>, AppState) {
    ...
}

/// Apply throttle, auth gate, middleware, and state to a base router,
/// producing the final `Router` ready for `axum::serve`.
pub fn finalize_gateway_app(
    router: Router<AppState>,
    app_state: AppState,
    http_request_logs: bool,
) -> Router {
    ...
}

/// Convenience wrapper: build base + finalize in one call (used by tests).
#[cfg(feature = "push-notifications")]
pub fn build_gateway_app(
    state: Arc<GatewayState>,
    methods: Arc<MethodRegistry>,
    push_service: Option<Arc<crate::push::PushService>>,
    http_request_logs: bool,
    webauthn_registry: Option<SharedWebAuthnRegistry>,
) -> Router {
    ...
}

/// Convenience wrapper: build base + finalize in one call (used by tests).
#[cfg(not(feature = "push-notifications"))]
pub fn build_gateway_app(
    state: Arc<GatewayState>,
    methods: Arc<MethodRegistry>,
    http_request_logs: bool,
    webauthn_registry: Option<SharedWebAuthnRegistry>,
) -> Router {
    ...
}

fn env_var_or_unset(name: &str) -> String {
    ...
}

fn env_flag_enabled(name: &str) -> bool {
    ...
}

fn process_rss_bytes() -> u64 {
    ...
}

struct StartupMemProbe {
    ...
}

impl StartupMemProbe {
    fn new() -> Self {

    fn checkpoint(&mut self, stage: &str) {
    ...
}
}

fn validate_proxy_tls_configuration(
    behind_proxy: bool,
    tls_enabled: bool,
    allow_tls_behind_proxy: bool,
) -> anyhow::Result<()> {
    ...
}

fn log_path_diagnostics(kind: &str, path: &FsPath) {
    ...
}

fn log_directory_write_probe(dir: &FsPath) {
    ...
}

#[cfg(feature = "openclaw-import")]
fn detect_openclaw_with_startup_logs() -> Option<moltis_openclaw_import::OpenClawDetection> {
    ...
}

#[cfg(feature = "openclaw-import")]
fn deferred_openclaw_status() -> String {
    ...
}

#[cfg(not(feature = "openclaw-import"))]
fn deferred_openclaw_status() -> String {
    ...
}

#[cfg(feature = "openclaw-import")]
#[cfg_attr(not(feature = "file-watcher"), allow(unused_variables))]
fn spawn_openclaw_background_init(data_dir: PathBuf) {
    ...
}

#[cfg(not(feature = "openclaw-import"))]
fn spawn_openclaw_background_init(_data_dir: PathBuf) {
    ...
}