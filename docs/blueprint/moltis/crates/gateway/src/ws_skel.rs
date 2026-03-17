use std::{collections::HashMap, net::SocketAddr, sync::Arc};

use {
    axum::extract::ws::{Message, WebSocket},
    futures::{SinkExt, stream::StreamExt},
    tokio::sync::mpsc,
    tracing::{debug, info, warn},
};

use moltis_protocol::{
    ConnectParams, ConnectParamsV4, ErrorShape, EventFrame, Extensions, Features, GatewayFrame,
    HANDSHAKE_TIMEOUT_MS, HelloAuth, HelloOk, KNOWN_EVENTS, MAX_PAYLOAD_BYTES, PROTOCOL_VERSION,
    Policy, ResponseFrame, ServerInfo, error_codes, roles, scopes,
};

use crate::{
    auth,
    broadcast::{BroadcastOpts, broadcast},
    methods::{MethodContext, MethodRegistry},
    nodes::NodeSession,
    state::{ConnectedClient, GatewayState},
};

fn top_level_param_keys(params: &Option<serde_json::Value>) -> Vec<String> {
    ...
}

/// Handle a single WebSocket connection through its full lifecycle:
/// handshake (with auth) → message loop → cleanup.
pub async fn handle_connection(
    socket: WebSocket,
    state: Arc<GatewayState>,
    methods: Arc<MethodRegistry>,
    remote_addr: SocketAddr,
    accept_language: Option<String>,
    remote_ip: Option<String>,
    header_authenticated: bool,
    is_local: bool,
) {
    ...
}

/// Result of parsing connect params: includes whether v4 format was used.
struct ConnectResult {
    ...
}

async fn graceful_writer_shutdown(
    client_tx: mpsc::Sender<String>,
    write_handle: tokio::task::JoinHandle<()>,
) {
    ...
}

/// Wait for the first `connect` request frame. Tries v4 format first, falls back to v3.
async fn wait_for_connect(
    rx: &mut futures::stream::SplitStream<WebSocket>,
) -> anyhow::Result<ConnectResult> {
    ...
}
