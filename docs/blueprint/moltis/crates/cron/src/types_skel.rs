//! Core data types for the cron scheduling system.

use serde::{Deserialize, Serialize};

/// Whether to wake the heartbeat after a cron job completes.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum CronWakeMode {
    ...
}

/// How a job is scheduled.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum CronSchedule {
    ...
}

/// What happens when a job fires.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum CronPayload {
    ...
}

/// Where the job executes.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SessionTarget {
    ...
}

/// Outcome of a single job run.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum RunStatus {
    ...
}

/// Mutable runtime state of a job.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct CronJobState {
    ...
}

/// A scheduled cron job.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CronJob {
    ...
}

/// Record of a completed run, stored in run history.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CronRunRecord {
    ...
}

/// Sandbox configuration for a cron job.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CronSandboxConfig {
    ...
}

impl Default for CronSandboxConfig {
    fn default() -> Self {
}

/// Input for creating a new job.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CronJobCreate {
    ...
}

fn default_true() -> bool {
    ...
}

/// Patch for updating an existing job.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct CronJobPatch {
    ...
}

/// Summary status of the cron system.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CronStatus {
    ...
}

/// Notification emitted when cron jobs change.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum CronNotification {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_schedule_roundtrip_every() {
    ...
}

    #[test]
    fn test_schedule_roundtrip_cron() {
    ...
}

    #[test]
    fn test_payload_system_event() {
    ...
}

    #[test]
    fn test_payload_agent_turn() {
    ...
}

    #[test]
    fn test_cronjob_roundtrip() {
    ...
}

    #[test]
    fn test_session_target_default_is_isolated() {
    ...
}

    #[test]
    fn test_run_record_roundtrip() {
    ...
}

    #[test]
    fn test_run_record_with_tokens() {
    ...
}

    #[test]
    fn test_run_record_deserialize_without_tokens() {
    ...
}

    #[test]
    fn test_job_create_defaults() {
    ...
}

    #[test]
    fn test_sandbox_config_default() {
    ...
}

    #[test]
    fn test_sandbox_config_roundtrip() {
    ...
}

    #[test]
    fn test_sandbox_config_deserialize_missing_defaults() {
    ...
}

    #[test]
    fn test_cronjob_with_sandbox_roundtrip() {
    ...
}

    #[test]
    fn test_cron_status_serialize() {
    ...
}

    #[test]
    fn test_wake_mode_serde_roundtrip() {
    ...
}

    #[test]
    fn test_wake_mode_default() {
    ...
}

    #[test]
    fn test_wake_mode_backward_compat_missing_field() {
    ...
}

    #[test]
    fn test_cronjob_create_with_wake_mode() {
    ...
}

    #[test]
    fn test_cronjob_patch_with_wake_mode() {
    ...
}
}
