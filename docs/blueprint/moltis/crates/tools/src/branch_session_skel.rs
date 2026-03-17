//! Agent tool for forking the current session into a new branch.

use std::sync::Arc;

use {
    async_trait::async_trait,
    moltis_agents::tool_registry::AgentTool,
    moltis_sessions::{metadata::SqliteSessionMetadata, store::SessionStore},
    serde_json::{Value, json},
};

use crate::error::Error;

/// Agent tool that forks the current session at a given message index.
pub struct BranchSessionTool {
    ...
}

impl BranchSessionTool {
    pub fn new(store: Arc<SessionStore>, metadata: Arc<SqliteSessionMetadata>) -> Self {
}

#[async_trait]
impl AgentTool for BranchSessionTool {
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

    fn user_message(text: impl Into<String>) -> Value {
    ...
}

    async fn setup() -> (
        Arc<SessionStore>,
        Arc<SqliteSessionMetadata>,
        tempfile::TempDir,
    ) {
    ...
}

    #[tokio::test]
    async fn test_branch_at_midpoint() {
    ...
}

    #[tokio::test]
    async fn test_fork_point_beyond_count() {
    ...
}

    #[tokio::test]
    async fn test_fork_all_messages() {
    ...
}
}
