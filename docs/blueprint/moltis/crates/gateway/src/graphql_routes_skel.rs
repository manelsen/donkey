//! GraphQL HTTP handlers for the gateway.
//!
//! These handlers bridge `AppState` to the `moltis-graphql` schema, providing
//! GraphiQL on GET `/graphql`, query/mutation execution on POST `/graphql`,
//! and WebSocket subscriptions on GET `/graphql`.

use std::sync::Arc;

use {
    async_graphql::http::{GraphiQLPlugin, GraphiQLSource},
    axum::{
        Json,
        extract::{FromRequestParts, Request, State, WebSocketUpgrade},
        http::{HeaderMap, StatusCode, header},
        response::{Html, IntoResponse, Response},
    },
    serde_json::Value,
};

use crate::{server::AppState, services::ServiceResult, state::GatewayState};

/// `SystemInfoService` implementation backed by the gateway's live state.
///
/// Covers methods that read gateway-internal data (connections, nodes, hooks,
/// heartbeat) rather than delegating to a domain service crate.
pub struct GatewaySystemInfoService {
    ...
}

#[async_trait::async_trait]
impl moltis_service_traits::SystemInfoService for GatewaySystemInfoService {
    async fn health(&self) -> ServiceResult {

    async fn status(&self) -> ServiceResult {
    ...
}

    async fn system_presence(&self) -> ServiceResult {
    ...
}

    async fn node_list(&self) -> ServiceResult {
    ...
}

    async fn node_describe(&self, params: Value) -> ServiceResult {
    ...
}

    async fn hooks_list(&self) -> ServiceResult {
    ...
}

    async fn heartbeat_status(&self) -> ServiceResult {
    ...
}

    async fn heartbeat_runs(&self, _params: Value) -> ServiceResult {
    ...
}
}

/// Handle GET `/graphql`:
///
/// - Standard HTTP GET: returns GraphiQL.
/// - WebSocket upgrade GET: upgrades to GraphQL subscriptions.
pub async fn graphql_get_handler(State(state): State<AppState>, req: Request) -> impl IntoResponse {
    ...
}

/// Handle GraphQL queries and mutations.
pub async fn graphql_handler(
    State(state): State<AppState>,
    req: async_graphql_axum::GraphQLRequest,
) -> impl IntoResponse {
    ...
}

fn graphql_ws_response(
    state: &AppState,
    protocol: async_graphql_axum::GraphQLProtocol,
    ws: WebSocketUpgrade,
) -> Response {
    ...
}

fn graphiql_response() -> Response {
    ...
}

fn graphql_disabled_response() -> Response {
    ...
}

fn is_websocket_upgrade_request(headers: &HeaderMap) -> bool {
    ...
}
