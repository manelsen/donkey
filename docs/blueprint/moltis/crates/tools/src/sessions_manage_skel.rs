//! Session management tools for creating and deleting chat sessions.
//!
//! These tools expose explicit session lifecycle operations to the agent:
//! - `sessions_create`: create (or resolve) a session key
//! - `sessions_delete`: delete a session and its history

use std::sync::Arc;

use {async_trait::async_trait, futures::future::BoxFuture, serde_json::Value};

use {moltis_agents::tool_registry::AgentTool, moltis_sessions::metadata::SqliteSessionMetadata};

use crate::{
    Error,
    params::{bool_param, owned_str_param, require_str, str_param},
};

/// Request payload for session creation.
#[derive(Debug, Clone)]
pub struct CreateSessionRequest {
    ...
}

/// Callback used by `sessions_create`.
pub type CreateSessionFn =
    Arc<dyn Fn(CreateSessionRequest) -> BoxFuture<'static, crate::Result<Value>> + Send + Sync>;

/// Request payload for session deletion.
#[derive(Debug, Clone)]
pub struct DeleteSessionRequest {
    ...
}

/// Callback used by `sessions_delete`.
pub type DeleteSessionFn =
    Arc<dyn Fn(DeleteSessionRequest) -> BoxFuture<'static, crate::Result<Value>> + Send + Sync>;

/// Tool for creating sessions.
pub struct SessionsCreateTool {
    ...
}

impl SessionsCreateTool {
    pub fn new(metadata: Arc<SqliteSessionMetadata>, create_fn: CreateSessionFn) -> Self {
}

/// Tool for deleting sessions.
pub struct SessionsDeleteTool {
    ...
}

impl SessionsDeleteTool {
    pub fn new(metadata: Arc<SqliteSessionMetadata>, delete_fn: DeleteSessionFn) -> Self {
}

#[async_trait]
impl AgentTool for SessionsCreateTool {
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

#[async_trait]
impl AgentTool for SessionsDeleteTool {
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

#[cfg(test)]
mod tests {

    use super::*;

    type TestResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

    async fn test_pool() -> TestResult<sqlx::SqlitePool> {
    ...
}

    #[tokio::test]
    async fn sessions_create_generates_key_when_missing() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn sessions_create_marks_existing_session_as_not_created() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn sessions_delete_deletes_existing_session() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn sessions_delete_rejects_missing_session() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn sessions_delete_rejects_main_session() -> TestResult<()> {
    ...
}
}
