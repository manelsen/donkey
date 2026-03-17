//! In-memory log capture layer and live logs service.
//!
//! [`LogBroadcastLayer`] is a `tracing_subscriber::Layer` that captures every
//! tracing event into a bounded ring buffer and broadcasts new entries to a
//! `tokio::sync::broadcast` channel for real-time streaming to WebSocket
//! clients.
//!
//! When persistence is enabled via [`LogBuffer::enable_persistence`], entries
//! are appended to a JSONL file. Historical entries are read lazily from the
//! file only when the UI requests them — nothing is loaded into memory at
//! startup.

use std::{
    collections::VecDeque,
    fs::{File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    sync::{
        Arc, Mutex, RwLock,
        atomic::{AtomicU64, Ordering},
    },
};

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    serde_json::Value,
    tokio::sync::broadcast,
    tracing::field::{Field, Visit},
    tracing_subscriber::{Layer, filter::LevelFilter, layer::Context},
};

use crate::services::{LogsService, ServiceResult};

// ── LogEntry ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    ...
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct EnabledLogLevels {
    ...
}

impl EnabledLogLevels {
    #[must_use]
    pub const fn from_max_level_hint(hint: Option<LevelFilter>) -> Self {
}

// ── LogBuffer ───────────────────────────────────────────────────────────────

const DEFAULT_CAPACITY: usize = 1_000;
const DEFAULT_BROADCAST_CAPACITY: usize = 512;

#[derive(Clone)]
pub struct LogBuffer {
    ...
}

impl LogBuffer {
    pub fn new(capacity: usize) -> Self {

    /// Enable file-backed persistence. New entries will be appended to `path`.
    /// Historical entries are **not** loaded into memory — they are read
    /// on-demand when [`Self::list_from_file`] is called.
    ///
    /// Scans the JSONL file once to seed warn/error counters, and loads acked
    /// counters from a sibling `.visited` file.
    pub fn enable_persistence(&self, path: PathBuf) {
    ...
}

    pub fn push(&self, entry: LogEntry) {
    ...
}

    pub fn subscribe(&self) -> broadcast::Receiver<LogEntry> {
    ...
}

    /// Return the last `limit` entries from the in-memory ring buffer only.
    pub fn list(&self, filter: &LogFilter, limit: usize) -> Vec<LogEntry> {
    ...
}

    /// Read the last `limit` matching entries from the persisted JSONL file.
    /// This scans the entire file but does not keep entries in memory beyond
    /// the returned vector.
    pub fn list_from_file(&self, filter: &LogFilter, limit: usize) -> Vec<LogEntry> {
    ...
}

    /// Return the path to the persisted JSONL file, if persistence is enabled.
    pub fn file_path(&self) -> Option<PathBuf> {
    ...
}

    /// O(1) count of unseen warn/error entries since the last ack.
    pub fn count_unseen(&self) -> (u64, u64) {
    ...
}

    /// Snapshot current totals as "seen" and persist to disk.
    pub fn ack_visit(&self) {
    ...
}

    pub fn set_enabled_levels(&self, levels: EnabledLogLevels) {
    ...
}

    #[must_use]
    pub fn enabled_levels(&self) -> EnabledLogLevels {
    ...
}
}

impl Default for LogBuffer {
    fn default() -> Self {
}

// ── LogFilter ───────────────────────────────────────────────────────────────

pub struct LogFilter {
    ...
}

impl LogFilter {
    fn level_ord(l: &str) -> u8 {

    fn matches(&self, entry: &LogEntry) -> bool {
    ...
}
}

// ── Visitor (extracts fields from tracing events) ───────────────────────────

struct FieldVisitor {
    ...
}

impl FieldVisitor {
    fn new() -> Self {
}

impl Visit for FieldVisitor {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {

    fn record_str(&mut self, field: &Field, value: &str) {
    ...
}

    fn record_i64(&mut self, field: &Field, value: i64) {
    ...
}

    fn record_u64(&mut self, field: &Field, value: u64) {
    ...
}

    fn record_bool(&mut self, field: &Field, value: bool) {
    ...
}
}

// ── LogBroadcastLayer ───────────────────────────────────────────────────────

pub struct LogBroadcastLayer {
    ...
}

impl LogBroadcastLayer {
    pub fn new(buffer: LogBuffer) -> Self {
}

impl<S: tracing::Subscriber> Layer<S> for LogBroadcastLayer {
    fn on_event(&self, event: &tracing::Event<'_>, _ctx: Context<'_, S>) {
    ...
}
}

// ── LiveLogsService ─────────────────────────────────────────────────────────

pub struct LiveLogsService {
    ...
}

impl LiveLogsService {
    pub fn new(buffer: LogBuffer) -> Self {
}

#[async_trait]
impl LogsService for LiveLogsService {
    async fn tail(&self, params: Value) -> ServiceResult {

    async fn list(&self, params: Value) -> ServiceResult {
    ...
}

    async fn status(&self) -> ServiceResult {
    ...
}

    async fn ack(&self) -> ServiceResult {
    ...
}

    fn log_file_path(&self) -> Option<PathBuf> {
    ...
}
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn make_entry(level: &str, target: &str, message: &str) -> LogEntry {
    ...
}

    #[test]
    fn buffer_ring_evicts_oldest() {
    ...
}

    #[test]
    fn filter_by_level() {
    ...
}

    #[test]
    fn enabled_levels_from_max_hint() {
    ...
}

    #[test]
    fn filter_by_target() {
    ...
}

    #[test]
    fn filter_by_search() {
    ...
}

    #[test]
    fn list_respects_limit() {
    ...
}

    #[test]
    fn broadcast_receiver_gets_entries() {
    ...
}

    #[test]
    fn persistence_write_and_read_from_file() {
    ...
}

    #[test]
    fn persistence_survives_restart() {
    ...
}

    #[test]
    fn list_from_file_respects_filter_and_limit() {
    ...
}

    #[tokio::test]
    async fn live_logs_service_tail() {
    ...
}

    #[tokio::test]
    async fn live_logs_service_list_from_file() {
    ...
}

    #[tokio::test]
    async fn live_logs_service_list_falls_back_to_memory() {
    ...
}

    #[test]
    fn count_unseen_in_memory() {
    ...
}

    #[test]
    fn count_unseen_seeded_from_file() {
    ...
}

    #[test]
    fn ack_visit_persists() {
    ...
}

    #[tokio::test]
    async fn live_logs_service_status_and_ack() {
    ...
}

    #[test]
    fn file_path_none_without_persistence() {
    ...
}

    #[test]
    fn file_path_returns_path_with_persistence() {
    ...
}

    #[test]
    fn log_file_path_via_service() {
    ...
}

    #[test]
    fn log_file_path_none_without_persistence() {
    ...
}
}
