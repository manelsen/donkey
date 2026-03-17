//! WebSocket client that connects to a gateway as a headless node.

use std::{process::Stdio, time::Duration};

use {
    futures::{SinkExt, StreamExt},
    tokio::process::Command,
    tokio_tungstenite::{connect_async, tungstenite::Message},
    tracing::{debug, error, info, warn},
};

use moltis_protocol::{
    ClientInfo, ConnectAuth, ConnectParamsV4, GatewayFrame, PROTOCOL_VERSION, ProtocolRange,
    RequestFrame, ResponseFrame, roles,
};

/// Configuration for connecting a node to a gateway.
#[derive(Debug, Clone)]
pub struct NodeConfig {
    ...
}

impl Default for NodeConfig {
    fn default() -> Self {
}

/// Detect installed runtimes using `which`.
fn detect_runtimes() -> Vec<String> {
    ...
}

/// Collect system telemetry using `sysinfo`.
fn collect_system_telemetry(node_id: &str) -> serde_json::Value {
    ...
}

/// A headless node host that connects to a gateway and handles commands.
pub struct NodeHost {
    ...
}

impl NodeHost {
    pub fn new(config: NodeConfig) -> Self {

    /// Connect to the gateway and run the message loop until disconnected.
    ///
    /// Returns `Ok(())` on clean shutdown, `Err` on connection/protocol errors.
    pub async fn run(&self) -> anyhow::Result<()> {
    ...
}

    async fn handle_message(
        &self,
        text: &str,
        ws_tx: &mut (impl SinkExt<Message, Error = tokio_tungstenite::tungstenite::Error> + Unpin),
    ) {
    ...
}

    async fn handle_invoke(
        &self,
        payload: Option<serde_json::Value>,
        ws_tx: &mut (impl SinkExt<Message, Error = tokio_tungstenite::tungstenite::Error> + Unpin),
    ) {
    ...
}

    async fn handle_system_run(
        &self,
        args: &serde_json::Value,
    ) -> anyhow::Result<serde_json::Value> {
    ...
}

    async fn handle_system_which(
        &self,
        args: &serde_json::Value,
    ) -> anyhow::Result<serde_json::Value> {
    ...
}

    async fn handle_system_providers(&self) -> anyhow::Result<serde_json::Value> {
    ...
}

    async fn send_invoke_result(
        &self,
        invoke_id: &str,
        result: serde_json::Value,
        ws_tx: &mut (impl SinkExt<Message, Error = tokio_tungstenite::tungstenite::Error> + Unpin),
    ) {
    ...
}

    async fn send_telemetry(
        &self,
        ws_tx: &mut (impl SinkExt<Message, Error = tokio_tungstenite::tungstenite::Error> + Unpin),
    ) {
    ...
}

    async fn send_invoke_error(
        &self,
        invoke_id: &str,
        error: &str,
        ws_tx: &mut (impl SinkExt<Message, Error = tokio_tungstenite::tungstenite::Error> + Unpin),
    ) {
    ...
}
}

#[cfg(test)]
mod tests {

    #[test]
    fn default_config_platform_is_current_os() {
    ...
}

    #[tokio::test]
    async fn system_which_finds_sh() {
    ...
}

    #[tokio::test]
    async fn system_which_missing_binary() {
    ...
}

    #[tokio::test]
    async fn system_run_echo() {
    ...
}

    #[tokio::test]
    async fn system_run_captures_stderr() {
    ...
}

    #[tokio::test]
    async fn system_run_exit_code() {
    ...
}
}
