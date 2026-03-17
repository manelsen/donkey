//! MCP health polling and auto-restart background task.

use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};

use tracing::{info, warn};

use crate::{
    broadcast::{BroadcastOpts, broadcast},
    mcp_service::LiveMcpService,
    state::GatewayState,
};

const POLL_INTERVAL: Duration = Duration::from_secs(30);
const MAX_RESTART_ATTEMPTS: u32 = 5;
const BASE_BACKOFF: Duration = Duration::from_secs(5);
const MAX_BACKOFF: Duration = Duration::from_secs(300);

struct RestartState {
    ...
}

/// Run the health monitor loop. Checks all MCP servers periodically,
/// broadcasts status changes, and auto-restarts dead servers with backoff.
pub async fn run_health_monitor(state: Arc<GatewayState>, mcp: Arc<LiveMcpService>) {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_max_backoff_cap() {
    ...
}
}
