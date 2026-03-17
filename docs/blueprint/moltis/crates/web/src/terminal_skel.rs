use std::{
    io::{Read, Write},
    net::SocketAddr,
    path::PathBuf,
    process::Command,
    sync::Arc,
};

use {
    axum::{
        Json,
        extract::{
            ConnectInfo, Query, State, WebSocketUpgrade,
            ws::{Message, WebSocket},
        },
        http::StatusCode,
        response::IntoResponse,
    },
    base64::Engine as _,
    futures::{SinkExt, StreamExt},
    moltis_gateway::server::AppState,
    portable_pty::{CommandBuilder, PtySize, native_pty_system},
    tracing::{debug, info, warn},
};

// ── Constants ────────────────────────────────────────────────────────────────

const HOST_TERMINAL_SESSION_NAME: &str = "moltis-host-terminal";
const HOST_TERMINAL_TMUX_SOCKET_NAME: &str = "moltis-host-terminal";
const HOST_TERMINAL_TMUX_CONFIG_PATH: &str = "/dev/null";
const HOST_TERMINAL_MAX_INPUT_BYTES: usize = 8 * 1024;
const HOST_TERMINAL_DEFAULT_COLS: u16 = 220;
const HOST_TERMINAL_DEFAULT_ROWS: u16 = 56;
const TERMINAL_SESSION_INIT_FAILED: &str = "TERMINAL_SESSION_INIT_FAILED";
const TERMINAL_WINDOWS_LIST_FAILED: &str = "TERMINAL_WINDOWS_LIST_FAILED";
const TERMINAL_TMUX_UNAVAILABLE: &str = "TERMINAL_TMUX_UNAVAILABLE";
const TERMINAL_WINDOW_NAME_INVALID: &str = "TERMINAL_WINDOW_NAME_INVALID";
const TERMINAL_WINDOW_CREATE_FAILED: &str = "TERMINAL_WINDOW_CREATE_FAILED";

// ── Data structures ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, Default, serde::Deserialize)]
pub struct HostTerminalWsQuery {
    ...
}

#[derive(Debug, Clone, serde::Serialize)]
struct HostTerminalWindowInfo {
    ...
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct HostTerminalCreateWindowRequest {
    ...
}

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum HostTerminalWsClientMessage {
    ...
}

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
enum HostTerminalWsControlAction {
    ...
}

enum HostTerminalOutputEvent {
    ...
}

struct HostTerminalPtyRuntime {
    ...
}

#[derive(Debug, thiserror::Error)]
#[error("{message}")]
struct TerminalError {
    ...
}

impl From<String> for TerminalError {
    fn from(message: String) -> Self {
}

impl From<&str> for TerminalError {
    fn from(message: &str) -> Self {
}

type TerminalResult<T> = Result<T, TerminalError>;

// ── Helpers ──────────────────────────────────────────────────────────────────

fn terminal_error(code: &str, error: impl Into<String>) -> serde_json::Value {
    ...
}

fn host_terminal_working_dir() -> Option<PathBuf> {
    ...
}

fn host_terminal_user_name() -> String {
    ...
}

fn host_terminal_tmux_available() -> bool {
    ...
}

fn tmux_install_command_for_linux(
    has_debian: bool,
    has_redhat: bool,
    has_arch: bool,
    has_alpine: bool,
) -> &'static str {
    ...
}

fn tmux_install_command_for_host_os() -> Option<&'static str> {
    ...
}

fn host_terminal_tmux_install_hint() -> Option<String> {
    ...
}

fn host_terminal_apply_env(cmd: &mut CommandBuilder) {
    ...
}

fn host_terminal_apply_tmux_common_args(cmd: &mut CommandBuilder) {
    ...
}

fn host_terminal_tmux_command() -> Command {
    ...
}

fn host_terminal_apply_tmux_profile() {
    ...
}

fn host_terminal_normalize_window_name(name: &str) -> TerminalResult<String> {
    ...
}

fn host_terminal_normalize_window_target(target: &str) -> Option<String> {
    ...
}

fn host_terminal_resolve_window_target(
    windows: &[HostTerminalWindowInfo],
    requested: &str,
) -> Option<String> {
    ...
}

fn host_terminal_default_window_target(windows: &[HostTerminalWindowInfo]) -> Option<String> {
    ...
}

fn host_terminal_ensure_tmux_session() -> TerminalResult<()> {
    ...
}

fn host_terminal_parse_tmux_window_line(line: &str) -> Option<HostTerminalWindowInfo> {
    ...
}

fn host_terminal_tmux_list_windows() -> TerminalResult<Vec<HostTerminalWindowInfo>> {
    ...
}

fn host_terminal_tmux_create_window(name: Option<&str>) -> TerminalResult<String> {
    ...
}

fn host_terminal_tmux_select_window(window_target: &str) -> TerminalResult<()> {
    ...
}

fn host_terminal_tmux_reset_window_size(window_target: Option<&str>) {
    ...
}

fn host_terminal_command_builder(use_tmux_persistence: bool) -> CommandBuilder {
    ...
}

fn spawn_host_terminal_runtime(
    cols: u16,
    rows: u16,
    use_tmux_persistence: bool,
    tmux_window_target: Option<&str>,
) -> TerminalResult<HostTerminalPtyRuntime> {
    ...
}

fn spawn_host_terminal_reader(
    mut reader: Box<dyn Read + Send>,
) -> TerminalResult<tokio::sync::mpsc::UnboundedReceiver<HostTerminalOutputEvent>> {
    ...
}

fn host_terminal_write_input(
    runtime: &mut HostTerminalPtyRuntime,
    input: &str,
) -> TerminalResult<()> {
    ...
}

fn host_terminal_resize(
    runtime: &HostTerminalPtyRuntime,
    cols: u16,
    rows: u16,
) -> TerminalResult<()> {
    ...
}

fn host_terminal_stop_runtime(runtime: &mut HostTerminalPtyRuntime) {
    ...
}

fn detect_host_root_user_for_terminal() -> Option<bool> {
    ...
}

// ── Auth / origin helpers (needed by terminal WS handler) ────────────────────

/// Returns `true` when the request carries headers typically set by reverse proxies.
fn has_proxy_headers(headers: &axum::http::HeaderMap) -> bool {
    ...
}

/// Returns `true` when `host` (without port) is a loopback name/address.
fn is_loopback_host(host: &str) -> bool {
    ...
}

/// Determine whether a connection is a **direct local** connection (no proxy
/// in between).  This is the per-request check used by the three-tier auth
/// model:
///
/// 1. Password set -> always require auth
/// 2. No password + local -> full access (dev convenience)
/// 3. No password + remote/proxied -> onboarding only
///
/// A connection is considered local when **all** of the following hold:
///
/// - `MOLTIS_BEHIND_PROXY` is **not** set (`behind_proxy == false`)
/// - No proxy headers are present (X-Forwarded-For, X-Real-IP, etc.)
/// - The `Host` header resolves to a loopback address (or is absent)
/// - The TCP source IP is loopback
fn is_local_connection(
    headers: &axum::http::HeaderMap,
    remote_addr: SocketAddr,
    behind_proxy: bool,
) -> bool {
    ...
}

async fn websocket_header_authenticated(
    headers: &axum::http::HeaderMap,
    credential_store: Option<&Arc<moltis_gateway::auth::CredentialStore>>,
    is_local: bool,
) -> bool {
    ...
}

/// Check whether a WebSocket `Origin` header matches the request `Host`.
///
/// Extracts the host portion of the origin URL and compares it to the Host
/// header.  Accepts `localhost`, `127.0.0.1`, and `[::1]` interchangeably
/// so that `http://localhost:8080` matches a Host of `127.0.0.1:8080`.
fn is_same_origin(origin: &str, host: &str) -> bool {
    ...
}

// ── Payload builders ─────────────────────────────────────────────────────────

fn host_terminal_windows_payload(
    windows: Vec<HostTerminalWindowInfo>,
    session_name: Option<&str>,
) -> serde_json::Value {
    ...
}

// ── HTTP handlers ────────────────────────────────────────────────────────────

pub async fn api_terminal_windows_handler() -> impl IntoResponse {
    ...
}

pub async fn api_terminal_windows_create_handler(
    Json(payload): Json<HostTerminalCreateWindowRequest>,
) -> impl IntoResponse {
    ...
}

/// Dedicated host terminal WebSocket stream (`Settings > Terminal`).
pub async fn api_terminal_ws_upgrade_handler(
    ws: WebSocketUpgrade,
    Query(query): Query<HostTerminalWsQuery>,
    headers: axum::http::HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ...
}

// ── WebSocket helpers ────────────────────────────────────────────────────────

async fn terminal_ws_send_json(
    ws_tx: &mut futures::stream::SplitSink<WebSocket, Message>,
    payload: serde_json::Value,
) -> bool {
    ...
}

async fn terminal_ws_send_status(
    ws_tx: &mut futures::stream::SplitSink<WebSocket, Message>,
    text: impl std::fmt::Display,
    level: &str,
) -> bool {
    ...
}

async fn terminal_ws_send_output(
    ws_tx: &mut futures::stream::SplitSink<WebSocket, Message>,
    data: &[u8],
) -> bool {
    ...
}

// ── WebSocket connection handler ─────────────────────────────────────────────

async fn handle_terminal_ws_connection(
    socket: WebSocket,
    remote_addr: SocketAddr,
    requested_window: Option<String>,
) {
    ...
}
