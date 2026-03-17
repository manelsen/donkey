//! Core cron scheduler: timer loop, job execution, CRUD operations.

use std::{
    collections::VecDeque,
    future::Future,
    pin::Pin,
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use {
    tokio::{
        sync::{Mutex, Notify, RwLock},
        task::JoinHandle,
    },
    tracing::{debug, error, info, warn},
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, cron as cron_metrics, gauge, histogram};

use crate::{
    Error, Result, schedule::compute_next_run, store::CronStore, system_events::SystemEventsQueue,
    types::*,
};

/// Result of an agent turn, including optional token usage.
#[derive(Debug, Clone)]
pub struct AgentTurnResult {
    ...
}

/// Callback for running an isolated agent turn.
pub type AgentTurnFn = Arc<
    dyn Fn(AgentTurnRequest) -> Pin<Box<dyn Future<Output = Result<AgentTurnResult>> + Send>>
        + Send
        + Sync,
>;

/// Callback for injecting a system event into the main session.
pub type SystemEventFn = Arc<dyn Fn(String) + Send + Sync>;

/// Callback for notifying about cron job changes.
pub type NotifyFn = Arc<dyn Fn(CronNotification) + Send + Sync>;

/// Rate limiting configuration for cron job creation.
#[derive(Debug, Clone)]
pub struct RateLimitConfig {
    ...
}

impl Default for RateLimitConfig {
    fn default() -> Self {
}

/// Simple sliding-window rate limiter.
struct RateLimiter {
    ...
}

impl RateLimiter {
    fn new(config: RateLimitConfig) -> Self {

    /// Check if a new job can be created. Returns Ok(()) if allowed, Err if rate limited.
    fn check(&mut self) -> Result<()> {
    ...
}
}

/// Parameters passed to the agent turn callback.
#[derive(Debug, Clone)]
pub struct AgentTurnRequest {
    ...
}

/// The cron scheduler.
pub struct CronService {
    ...
}

/// Max time a job can be in "running" state before we consider it stuck (2 hours).
const STUCK_THRESHOLD_MS: u64 = 2 * 60 * 60 * 1000;

fn now_ms() -> u64 {
    ...
}

impl CronService {
    pub fn new(
        store: Arc<dyn CronStore>,
        on_system_event: SystemEventFn,
        on_agent_turn: AgentTurnFn,
    ) -> Arc<Self> {

    /// Create a new cron service with a notification callback.
    pub fn with_notify(
        store: Arc<dyn CronStore>,
        on_system_event: SystemEventFn,
        on_agent_turn: AgentTurnFn,
        on_notify: NotifyFn,
    ) -> Arc<Self> {
    ...
}

    /// Create a new cron service with all configuration options.
    pub fn with_config(
        store: Arc<dyn CronStore>,
        on_system_event: SystemEventFn,
        on_agent_turn: AgentTurnFn,
        on_notify: Option<NotifyFn>,
        rate_limit_config: RateLimitConfig,
    ) -> Arc<Self> {
    ...
}

    /// Create a new cron service with a pre-created events queue.
    ///
    /// Use this when the queue must be shared with closures created before
    /// the service (e.g. the `on_agent_turn` callback).
    pub fn with_events_queue(
        store: Arc<dyn CronStore>,
        on_system_event: SystemEventFn,
        on_agent_turn: AgentTurnFn,
        on_notify: Option<NotifyFn>,
        rate_limit_config: RateLimitConfig,
        events_queue: Arc<SystemEventsQueue>,
    ) -> Arc<Self> {
    ...
}

    /// Access the shared events queue for enqueueing system events.
    pub fn events_queue(&self) -> &Arc<SystemEventsQueue> {
    ...
}

    /// Wake the heartbeat by setting its next run to now.
    ///
    /// Multiple wake calls coalesce naturally: they all set `next_run_at_ms = now`
    /// idempotently, and `running_at_ms` prevents the heartbeat from firing twice.
    pub async fn wake(&self, reason: &str) {
    ...
}

    /// Emit a notification if a callback is registered.
    fn notify(&self, notification: CronNotification) {
    ...
}

    /// Load jobs from store and start the timer loop.
    pub async fn start(self: &Arc<Self>) -> Result<()> {
    ...
}

    /// Stop the timer loop.
    pub async fn stop(&self) {
    ...
}

    /// Add a new job.
    pub async fn add(&self, create: CronJobCreate) -> Result<CronJob> {
    ...
}

    /// Update an existing job.
    pub async fn update(&self, id: &str, patch: CronJobPatch) -> Result<CronJob> {
    ...
}

    /// Remove a job.
    pub async fn remove(&self, id: &str) -> Result<()> {
    ...
}

    /// List all jobs.
    pub async fn list(&self) -> Vec<CronJob> {
    ...
}

    /// Force-run a job immediately.
    pub async fn run(self: &Arc<Self>, id: &str, force: bool) -> Result<()> {
    ...
}

    /// Get run history for a job.
    pub async fn runs(&self, job_id: &str, limit: usize) -> Result<Vec<CronRunRecord>> {
    ...
}

    /// Get scheduler status.
    /// Counts exclude system jobs (e.g. heartbeat) to match what the UI shows.
    pub async fn status(&self) -> CronStatus {
    ...
}

    // ── Internal ────────────────────────────────────────────────────────

    async fn timer_loop(self: &Arc<Self>) {
    ...
}

    async fn ms_until_next_wake(&self) -> u64 {
    ...
}

    async fn process_due_jobs(self: &Arc<Self>) {
    ...
}

    async fn execute_job(self: &Arc<Self>, job: &CronJob) {
    ...
}

    async fn update_job_state<F: FnOnce(&mut CronJobState)>(&self, id: &str, f: F) {
        let mut jobs = self.jobs.write().await;
        if let Some(job) = jobs.iter_mut().find(|j| j.id == id) {
            f(&mut job.state);
        }
    }

    async fn recompute_all_next_runs(&self) {
    ...
}

    async fn clear_stuck_jobs(&self, now: u64) {
    ...
}
}

/// Validate session_target + payload compatibility.
fn validate_job_spec(job: &CronJob) -> Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
