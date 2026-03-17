//! In-memory event buffer that the heartbeat drains.
//!
//! Background processes (cron jobs, exec completions) enqueue events here.
//! On the next heartbeat tick the queue is drained, and event summaries are
//! prepended to the heartbeat prompt so the LLM can relay noteworthy items.

use std::{
    collections::VecDeque,
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use tokio::sync::Mutex;

/// Maximum events retained before oldest entries are dropped.
const MAX_EVENTS: usize = 20;

/// A single system event waiting for the heartbeat to process.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SystemEvent {
    ...
}

/// Thread-safe, bounded, dedup-aware event buffer.
pub struct SystemEventsQueue {
    ...
}

impl SystemEventsQueue {
    /// Create a new empty queue.
    #[must_use]
    pub fn new() -> Arc<Self> {

    /// Enqueue an event. Consecutive duplicate `text` values are deduplicated.
    /// When the buffer exceeds [`MAX_EVENTS`], the oldest entry is dropped.
    pub async fn enqueue(&self, text: String, reason: String) {
    ...
}

    /// Drain all pending events, returning them in FIFO order.
    pub async fn drain(&self) -> Vec<SystemEvent> {
    ...
}

    /// Peek at all pending events without removing them.
    pub async fn peek(&self) -> Vec<SystemEvent> {
    ...
}

    /// Check whether the queue is empty.
    pub async fn is_empty(&self) -> bool {
    ...
}
}

impl Default for SystemEventsQueue {
    fn default() -> Self {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn dedup_consecutive_identical() {
    ...
}

    #[tokio::test]
    async fn capacity_drops_oldest() {
    ...
}

    #[tokio::test]
    async fn peek_does_not_remove() {
    ...
}

    #[tokio::test]
    async fn drain_empty() {
    ...
}

    #[tokio::test]
    async fn enqueued_at_ms_is_set() {
    ...
}
}
