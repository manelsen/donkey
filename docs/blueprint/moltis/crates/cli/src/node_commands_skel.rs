use {anyhow::Result, clap::Subcommand, std::time::Duration};

/// `moltis node` subcommands — manage remote nodes.
#[derive(Subcommand)]
pub enum NodeAction {
    ...
}

pub async fn handle_node(action: NodeAction) -> Result<()> {
    ...
}

// ── Gateway RPC helpers ─────────────────────────────────────────────────���──

/// Call `device.token.create` on the gateway and print the token + command.
async fn cmd_generate_token(host: &str, api_key: Option<&str>, name: Option<&str>) -> Result<()> {
    ...
}

/// Call `node.list` on the gateway and print connected nodes.
async fn cmd_list(host: &str, api_key: Option<&str>) -> Result<()> {
    ...
}

/// Send a single RPC request to the gateway over HTTP (JSON-RPC style).
///
/// The gateway exposes RPC methods over the WebSocket protocol, but for
/// one-shot CLI commands we use the `/api/rpc` endpoint when available,
/// falling back to a transient WebSocket connection.
async fn gateway_rpc(
    host: &str,
    api_key: Option<&str>,
    method: &str,
    params: serde_json::Value,
) -> Result<serde_json::Value> {
    ...
}

/// Convert `http://host:port` to `ws://host:port/ws`.
fn http_to_ws(http_url: &str) -> String {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn http_to_ws_https() {
    ...
}

    #[test]
    fn http_to_ws_trailing_slash() {
    ...
}
}
