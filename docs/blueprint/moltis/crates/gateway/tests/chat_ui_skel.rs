#![allow(clippy::unwrap_used, clippy::expect_used)]
//! Integration tests for the embedded chat UI and WebSocket handshake.

use std::{net::SocketAddr, sync::Arc};

use {
    futures::{SinkExt, StreamExt},
    tokio::net::TcpListener,
    tokio_tungstenite::{connect_async, tungstenite::Message},
};

use moltis_gateway::{
    auth,
    chat::{DisabledModelsStore, LiveChatService, LiveModelService},
    methods::MethodRegistry,
    server::{build_gateway_base, finalize_gateway_app},
    services::GatewayServices,
    state::GatewayState,
};

use moltis_providers::ProviderRegistry;

/// Spin up a test gateway on an ephemeral port, return the bound address.
async fn start_test_server() -> SocketAddr {
    ...
}

#[cfg(feature = "web-ui")]
#[tokio::test]
async fn root_redirects_to_onboarding_when_not_onboarded() {
    ...
}

#[tokio::test]
async fn health_endpoint_returns_json() {
    ...
}

#[tokio::test]
async fn ws_handshake_returns_hello_ok() {
    ...
}

#[tokio::test]
async fn ws_health_method_after_handshake() {
    ...
}

#[tokio::test]
async fn ws_system_presence_shows_connected_client() {
    ...
}

/// Reproduce the full `start_gateway` init sequence (with provider wiring)
/// inside an async runtime. This catches panics like "Cannot block the current
/// thread from within a runtime" that only surface at run time.
#[tokio::test]
async fn gateway_startup_with_llm_wiring_does_not_block() {
    ...
}
