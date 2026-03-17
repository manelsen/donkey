//! In-memory ring buffer for network audit logs.
//!
//! Bounded ring buffer with a `tokio::sync::broadcast` channel for real-time
//! streaming, plus optional JSONL file persistence.

use std::{
    collections::VecDeque,
    fs::{File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    sync::{Arc, Mutex, RwLock},
};

use {serde_json, tokio::sync::broadcast};

use crate::{FilterOutcome, NetworkAuditEntry, NetworkProtocol};

// ── Filter ──────────────────────────────────────────────────────────────────

/// Filter criteria for audit log queries.
pub struct NetworkAuditFilter {
    ...
}

impl NetworkAuditFilter {
    fn matches(&self, entry: &NetworkAuditEntry) -> bool {
}

// ── Buffer ──────────────────────────────────────────────────────────────────

const DEFAULT_CAPACITY: usize = 5000;
const DEFAULT_BROADCAST_CAPACITY: usize = 256;

#[derive(Clone)]
pub struct NetworkAuditBuffer {
    ...
}

impl NetworkAuditBuffer {
    pub fn new(capacity: usize) -> Self {

    /// Enable JSONL file persistence at `path`.
    pub fn enable_persistence(&self, path: PathBuf) {
    ...
}

    /// Push an entry: broadcast, persist, ring-buffer.
    pub fn push(&self, entry: NetworkAuditEntry) {
    ...
}

    pub fn subscribe(&self) -> broadcast::Receiver<NetworkAuditEntry> {
    ...
}

    /// Return the last `limit` matching entries from the in-memory ring buffer.
    pub fn list(&self, filter: &NetworkAuditFilter, limit: usize) -> Vec<NetworkAuditEntry> {
    ...
}

    /// Read the last `limit` matching entries from the persisted JSONL file.
    pub fn list_from_file(
        &self,
        filter: &NetworkAuditFilter,
        limit: usize,
    ) -> Vec<NetworkAuditEntry> {
    ...
}

    /// Compute aggregate stats from the in-memory buffer.
    pub fn stats(&self) -> NetworkAuditStats {
    ...
}

    pub fn file_path(&self) -> Option<PathBuf> {
    ...
}
}

impl Default for NetworkAuditBuffer {
    fn default() -> Self {
}

// ── Stats ───────────────────────────────────────────────────────────────────

#[derive(Debug, serde::Serialize)]
pub struct NetworkAuditStats {
    ...
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
