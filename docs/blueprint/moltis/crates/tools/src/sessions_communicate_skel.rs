//! Session communication tools for listing, inspecting, and messaging sessions.
//!
//! These tools expose cross-session coordination primitives:
//! - `sessions_list`: list sessions with optional filtering
//! - `sessions_history`: read paginated history from a session
//! - `sessions_send`: send a message to another session (async or sync)

use std::sync::Arc;

use {async_trait::async_trait, futures::future::BoxFuture, serde_json::Value};

use {
    moltis_agents::tool_registry::AgentTool,
    moltis_sessions::{metadata::SqliteSessionMetadata, store::SessionStore},
};

use crate::{
    Error,
    params::{bool_param, owned_str_param, require_str, str_param, u64_param},
};

/// Request payload for cross-session message delivery.
#[derive(Debug, Clone)]
pub struct SendToSessionRequest {
    ...
}

/// Callback used by `sessions_send`.
pub type SendToSessionFn =
    Arc<dyn Fn(SendToSessionRequest) -> BoxFuture<'static, crate::Result<Value>> + Send + Sync>;

/// Policy controlling which sessions an agent can access.
#[derive(Debug, Clone, Default)]
pub struct SessionAccessPolicy {
    ...
}

impl SessionAccessPolicy {
    /// Check if a session key is accessible under this policy.
    pub fn can_access(&self, key: &str) -> bool {
}

impl From<&moltis_config::SessionAccessPolicyConfig> for SessionAccessPolicy {
    fn from(config: &moltis_config::SessionAccessPolicyConfig) -> Self {
}

/// Tool for listing known sessions.
pub struct SessionsListTool {
    ...
}

impl SessionsListTool {
    pub fn new(metadata: Arc<SqliteSessionMetadata>) -> Self {

    /// Attach a session access policy for filtering.
    pub fn with_policy(mut self, policy: SessionAccessPolicy) -> Self {
    ...
}
}

/// Tool for reading history from a target session.
pub struct SessionsHistoryTool {
    ...
}

impl SessionsHistoryTool {
    pub fn new(store: Arc<SessionStore>, metadata: Arc<SqliteSessionMetadata>) -> Self {

    /// Attach a session access policy for filtering.
    pub fn with_policy(mut self, policy: SessionAccessPolicy) -> Self {
    ...
}
}

/// Tool for sending a message to another session.
pub struct SessionsSendTool {
    ...
}

impl SessionsSendTool {
    pub fn new(metadata: Arc<SqliteSessionMetadata>, send_fn: SendToSessionFn) -> Self {

    /// Attach a session access policy for filtering.
    pub fn with_policy(mut self, policy: SessionAccessPolicy) -> Self {
    ...
}
}

#[async_trait]
impl AgentTool for SessionsListTool {
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
impl AgentTool for SessionsHistoryTool {
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
impl AgentTool for SessionsSendTool {
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

    use super::*;

    type TestResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

    async fn test_pool() -> TestResult<sqlx::SqlitePool> {
    ...
}

    #[tokio::test]
    async fn sessions_list_filters_and_limits() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn sessions_history_reads_paginated_messages() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn sessions_history_rejects_missing_session() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn sessions_send_calls_callback_and_wraps_context() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn sessions_send_rejects_missing_target() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn test_list_filtered_by_key_prefix() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn test_send_denied_when_can_send_false() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn test_no_policy_allows_all() -> TestResult<()> {
    ...
}
}
