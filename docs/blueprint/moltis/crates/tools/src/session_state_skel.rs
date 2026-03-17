//! Agent tool for per-session persistent state.
//!
//! Provides a key-value store scoped to the current session and a namespace,
//! allowing skills and extensions to persist context across messages.

use std::sync::Arc;

use {
    async_trait::async_trait,
    moltis_agents::tool_registry::AgentTool,
    moltis_sessions::state_store::SessionStateStore,
    serde_json::{Value, json},
};

use crate::error::Error;

/// Agent tool exposing per-session key-value state operations.
pub struct SessionStateTool {
    ...
}

impl SessionStateTool {
    pub fn new(store: Arc<SessionStateStore>) -> Self {
}

#[async_trait]
impl AgentTool for SessionStateTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn make_tool(pool: sqlx::SqlitePool) -> SessionStateTool {
    ...
}

    #[tokio::test]
    async fn test_set_and_get_via_tool() {
    ...
}

    #[tokio::test]
    async fn test_list_via_tool() {
    ...
}

    #[tokio::test]
    async fn test_clear_via_tool() {
    ...
}

    #[tokio::test]
    async fn test_missing_session_key() {
    ...
}

    #[tokio::test]
    async fn test_unknown_operation() {
    ...
}
}
