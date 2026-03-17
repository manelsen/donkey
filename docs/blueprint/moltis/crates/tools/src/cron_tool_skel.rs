//! Agent-callable cron tool for managing scheduled jobs.

use std::sync::Arc;

use {
    async_trait::async_trait,
    serde_json::{Map, Value, json},
};

use crate::{Result, error::Error};

use {
    moltis_agents::tool_registry::AgentTool,
    moltis_cron::{
        parse::{parse_absolute_time_ms, parse_duration_ms},
        service::CronService,
        types::{CronJobCreate, CronJobPatch},
    },
};

/// The cron tool exposed to LLM agents.
pub struct CronTool {
    ...
}

impl CronTool {
    pub fn new(service: Arc<CronService>) -> Self {
}

fn take_alias(obj: &mut Map<String, Value>, canonical: &str, aliases: &[&str]) {
    ...
}

fn parse_epoch_millis(value: &Value, field: &str) -> Result<u64> {
    ...
}

fn parse_interval_millis(value: &Value, field: &str) -> Result<u64> {
    ...
}

fn parse_timeout_seconds(value: &Value, field: &str) -> Result<u64> {
    ...
}

fn normalize_schedule_kind(raw: &str) -> Option<&'static str> {
    ...
}

fn normalize_schedule_value(schedule: &mut Value) -> Result<()> {
    ...
}

fn normalize_payload_kind(raw: &str) -> Option<&'static str> {
    ...
}

fn prefers_system_event(session_target_hint: Option<&str>) -> bool {
    ...
}

fn normalize_payload_value(payload: &mut Value, session_target_hint: Option<&str>) -> Result<()> {
    ...
}

fn normalize_wake_mode(raw: &str) -> Option<&'static str> {
    ...
}

fn normalize_wake_mode_field(obj: &mut Map<String, Value>) -> Result<()> {
    ...
}

fn normalize_session_target_field(obj: &mut Map<String, Value>) {
    ...
}

fn normalize_execution_target(raw: &str) -> Option<bool> {
    ...
}

fn parse_sandbox_enabled(value: &Value, field: &str) -> Result<bool> {
    ...
}

fn normalize_sandbox_value(sandbox: &mut Value, field: &str) -> Result<()> {
    ...
}

fn normalize_sandbox_field(obj: &mut Map<String, Value>) -> Result<()> {
    ...
}

fn normalize_job_value(job: &Value) -> Result<Value> {
    ...
}

fn normalize_patch_value(patch: &Value) -> Result<Value> {
    ...
}

#[async_trait]
impl AgentTool for CronTool {
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

    fn noop_sys() -> SystemEventFn {
    ...
}

    fn noop_agent() -> AgentTurnFn {
    ...
}

    fn make_tool() -> CronTool {
    ...
}

    #[tokio::test]
    async fn test_status() {
    ...
}

    #[tokio::test]
    async fn test_list_empty() {
    ...
}

    #[tokio::test]
    async fn test_add_and_list() {
    ...
}

    #[tokio::test]
    async fn test_remove() {
    ...
}

    #[tokio::test]
    async fn test_unknown_action() {
    ...
}

    #[tokio::test]
    async fn test_runs_empty() {
    ...
}

    #[tokio::test]
    async fn test_add_accepts_cron_expression_string_schedule() {
    ...
}

    #[tokio::test]
    async fn test_add_infers_schedule_kind_from_expr_without_kind() {
    ...
}

    #[tokio::test]
    async fn test_add_infers_payload_kind_for_main_session() {
    ...
}

    #[tokio::test]
    async fn test_update_accepts_schedule_string_patch() {
    ...
}

    #[tokio::test]
    async fn test_add_accepts_alias_fields_and_duration_strings() {
    ...
}

    #[tokio::test]
    async fn test_add_accepts_execution_target_and_image() {
    ...
}

    #[tokio::test]
    async fn test_add_accepts_delivery_fields_for_agent_turn() {
    ...
}

    #[tokio::test]
    async fn test_update_accepts_host_execution_string() {
    ...
}

    #[tokio::test]
    async fn test_update_accepts_delivery_fields_in_patch() {
    ...
}

    #[test]
    fn test_parameters_schema_has_no_one_of() {
    ...
}

    #[tokio::test]
    async fn test_add_accepts_payload_string_shorthand() {
    ...
}

    #[tokio::test]
    async fn test_add_rejects_ambiguous_schedule_without_kind() {
    ...
}

    #[test]
    fn test_normalize_wake_mode_aliases() {
    ...
}

    #[tokio::test]
    async fn test_add_with_wake_mode() {
    ...
}

    #[tokio::test]
    async fn test_add_with_wake_mode_alias() {
    ...
}

    #[tokio::test]
    async fn test_update_wake_mode() {
    ...
}
}
