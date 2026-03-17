use std::{collections::HashMap, sync::Arc};

use {
    moltis_protocol::{EventFrame, StateVersion, scopes},
    tracing::{debug, warn},
};

use crate::state::GatewayState;

// ── Scope guards ─────────────────────────────────────────────────────────────

/// Events that require specific scopes to receive.
fn event_scope_guards() -> HashMap<&'static str, &'static [&'static str]> {
    ...
}

// ── Broadcast options ────────────────────────────────────────────────────────

#[derive(Default)]
pub struct BroadcastOpts {
    ...
}

// ── Broadcaster ──────────────────────────────────────────────────────────────

/// Broadcast events to all connected WebSocket clients, respecting scope
/// guards and dropping/closing slow consumers.
pub async fn broadcast(
    state: &Arc<GatewayState>,
    event: &str,
    payload: serde_json::Value,
    opts: BroadcastOpts,
) {
    ...
}

/// Broadcast a tick event with the current timestamp and memory stats.
fn tick_mem_payload(
    process_memory_bytes: u64,
    local_llama_cpp_bytes: u64,
    system_available_bytes: u64,
    system_total_bytes: u64,
) -> serde_json::Value {
    ...
}

pub async fn broadcast_tick(
    state: &Arc<GatewayState>,
    process_memory_bytes: u64,
    local_llama_cpp_bytes: u64,
    system_available_bytes: u64,
    system_total_bytes: u64,
) {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn tick_mem_payload_includes_llama_cpp_when_positive() {
    ...
}
}
