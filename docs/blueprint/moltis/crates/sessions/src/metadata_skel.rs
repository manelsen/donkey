use std::{
    cmp::Ordering,
    collections::HashMap,
    fs,
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};

use crate::Result;

/// A single session entry in the metadata index.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionEntry {
    ...
}

/// JSON file-backed index mapping session key → SessionEntry.
pub struct SessionMetadata {
    ...
}

fn now_ms() -> u64 {
    ...
}

fn compare_sidebar_order(lhs: &SessionEntry, rhs: &SessionEntry) -> Ordering {
    ...
}

impl SessionMetadata {
    /// Load metadata from disk, or create an empty index.
    pub fn load(path: PathBuf) -> Result<Self> {

    /// Persist metadata to disk.
    pub fn save(&self) -> Result<()> {
    ...
}

    /// Get an entry by key.
    pub fn get(&self, key: &str) -> Option<&SessionEntry> {
    ...
}

    /// Insert or update an entry. If key doesn't exist, creates a new entry.
    pub fn upsert(&mut self, key: &str, label: Option<String>) -> &SessionEntry {
    ...
}

    /// Update the model associated with a session.
    pub fn set_model(&mut self, key: &str, model: Option<String>) {
    ...
}

    /// Update message count and updated_at timestamp.
    pub fn touch(&mut self, key: &str, message_count: u32) {
    ...
}

    /// Set the project_id for a session.
    pub fn set_project_id(&mut self, key: &str, project_id: Option<String>) {
    ...
}

    /// Set the worktree branch for a session.
    pub fn set_worktree_branch(&mut self, key: &str, branch: Option<String>) {
    ...
}

    /// Set the sandbox_image for a session.
    pub fn set_sandbox_image(&mut self, key: &str, image: Option<String>) {
    ...
}

    /// Set the sandbox_enabled override for a session.
    pub fn set_sandbox_enabled(&mut self, key: &str, enabled: Option<bool>) {
    ...
}

    /// Set the mcp_disabled override for a session.
    pub fn set_mcp_disabled(&mut self, key: &str, disabled: Option<bool>) {
    ...
}

    /// Set the channel binding for a session.
    pub fn set_channel_binding(&mut self, key: &str, binding: Option<String>) {
    ...
}

    /// Assign (or unassign) a session to an agent persona.
    pub fn set_agent_id(&mut self, key: &str, agent_id: Option<String>) {
    ...
}

    /// Assign (or unassign) a session to a remote node.
    pub fn set_node_id(&mut self, key: &str, node_id: Option<String>) {
    ...
}

    /// List all sessions belonging to a given agent.
    pub fn list_by_agent_id(&self, agent_id: &str) -> Vec<SessionEntry> {
    ...
}

    /// Delete all sessions belonging to a given agent. Returns the number of
    /// sessions removed.
    pub fn delete_by_agent_id(&mut self, agent_id: &str) -> u64 {
    ...
}

    /// Remove an entry by key. Returns the removed entry if found.
    pub fn remove(&mut self, key: &str) -> Option<SessionEntry> {
    ...
}

    /// List all entries for sidebar rendering.
    /// `main` is pinned first, then sessions are sorted by recency.
    pub fn list(&self) -> Vec<SessionEntry> {
    ...
}
}

// ── SQLite-backed session metadata ──────────────────────────────────

/// SQLite-backed session metadata store.
pub struct SqliteSessionMetadata {
    ...
}

#[derive(sqlx::FromRow)]
struct SessionRow {
    ...
}

impl From<SessionRow> for SessionEntry {
    fn from(r: SessionRow) -> Self {
}

impl SqliteSessionMetadata {
    pub fn new(pool: sqlx::SqlitePool) -> Self {

    /// Create with an event bus that auto-publishes on mutations.
    pub fn with_event_bus(
        pool: sqlx::SqlitePool,
        bus: crate::session_events::SessionEventBus,
    ) -> Self {
    ...
}

    /// Accessor for the event bus (subscribers call `.subscribe()` on it).
    pub fn event_bus(&self) -> Option<&crate::session_events::SessionEventBus> {
    ...
}

    /// Publish an event if a bus is configured.
    fn emit(&self, event: crate::session_events::SessionEvent) {
    ...
}

    /// Initialize the sessions table schema.
    ///
    /// **Deprecated**: Schema is now managed by sqlx migrations in the gateway crate.
    /// This method is retained for tests that use in-memory databases.
    #[doc(hidden)]
    pub async fn init(pool: &sqlx::SqlitePool) -> Result<()> {
    ...
}

    pub async fn get(&self, key: &str) -> Option<SessionEntry> {
    ...
}

    /// Insert or update an entry. Returns the entry.
    pub async fn upsert(
        &self,
        key: &str,
        label: Option<String>,
    ) -> std::result::Result<SessionEntry, sqlx::Error> {
    ...
}

    pub async fn set_model(&self, key: &str, model: Option<String>) {
    ...
}

    pub async fn touch(&self, key: &str, message_count: u32) {
    ...
}

    /// Set imported timestamps and message counters without replacing them with "now".
    pub async fn set_timestamps_and_counts(
        &self,
        key: &str,
        created_at: u64,
        updated_at: u64,
        message_count: u32,
        last_seen_message_count: u32,
    ) {
    ...
}

    /// Store a short preview of the first user message for sidebar display.
    pub async fn set_preview(&self, key: &str, preview: Option<&str>) {
    ...
}

    /// Mark a session as "seen" by setting `last_seen_message_count` to the
    /// current `message_count`.
    pub async fn mark_seen(&self, key: &str) {
    ...
}

    pub async fn set_project_id(&self, key: &str, project_id: Option<String>) {
    ...
}

    pub async fn set_sandbox_image(&self, key: &str, image: Option<String>) {
    ...
}

    pub async fn set_sandbox_enabled(&self, key: &str, enabled: Option<bool>) {
    ...
}

    pub async fn set_worktree_branch(&self, key: &str, branch: Option<String>) {
    ...
}

    pub async fn set_mcp_disabled(&self, key: &str, disabled: Option<bool>) {
    ...
}

    pub async fn set_channel_binding(&self, key: &str, binding: Option<String>) {
    ...
}

    /// Assign (or unassign) a session to an agent persona.
    pub async fn set_agent_id(&self, key: &str, agent_id: Option<&str>) -> Result<()> {
    ...
}

    /// Assign (or unassign) a session to a remote node.
    pub async fn set_node_id(&self, key: &str, node_id: Option<&str>) -> Result<()> {
    ...
}

    /// List all sessions belonging to a given agent.
    pub async fn list_by_agent_id(&self, agent_id: &str) -> Result<Vec<SessionEntry>> {
    ...
}

    /// Delete all sessions belonging to a given agent (cascade).
    pub async fn delete_by_agent_id(&self, agent_id: &str) -> Result<u64> {
    ...
}

    /// Set the parent session key and fork point for a branched session.
    pub async fn set_parent(&self, key: &str, parent_key: Option<String>, fork_point: Option<u32>) {
    ...
}

    /// List all sessions that are children of the given parent key.
    pub async fn list_children(&self, parent_key: &str) -> Vec<SessionEntry> {
    ...
}

    pub async fn remove(&self, key: &str) -> Option<SessionEntry> {
    ...
}

    pub async fn list(&self) -> Vec<SessionEntry> {
    ...
}

    /// Get the active session key for a channel chat, if one has been explicitly set.
    pub async fn get_active_session(
        &self,
        channel_type: &str,
        account_id: &str,
        chat_id: &str,
    ) -> Option<String> {
    ...
}

    /// Set (upsert) the active session key for a channel chat.
    pub async fn set_active_session(
        &self,
        channel_type: &str,
        account_id: &str,
        chat_id: &str,
        session_key: &str,
    ) {
    ...
}

    /// List all sessions that have been bound to a given channel chat
    /// (i.e. sessions whose `channel_binding` JSON contains the matching chat_id + account_id).
    pub async fn list_channel_sessions(
        &self,
        channel_type: &str,
        account_id: &str,
        chat_id: &str,
    ) -> Vec<SessionEntry> {
    ...
}

    /// List all sessions bound to a given channel account (any chat).
    pub async fn list_account_sessions(
        &self,
        channel_type: &str,
        account_id: &str,
    ) -> Vec<SessionEntry> {
    ...
}

    /// Get all active session mappings for a given channel account.
    pub async fn list_active_sessions(
        &self,
        channel_type: &str,
        account_id: &str,
    ) -> Vec<(String, String)> {
    ...
}

    /// No-op — SQLite auto-persists.
    pub fn save(&self) -> Result<()> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_list_pins_main_then_sorts_by_recency() {
    ...
}

    #[test]
    fn test_save_and_reload() {
    ...
}

    #[test]
    fn test_remove() {
    ...
}

    async fn sqlite_pool() -> sqlx::SqlitePool {
    ...
}

    #[tokio::test]
    async fn test_sqlite_upsert_and_list() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_list_pins_main_then_sorts_by_recency() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_remove() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_touch() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_set_timestamps_and_counts() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_mark_seen() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_mark_seen_emits_patched_event() {
    ...
}

    #[test]
    fn test_touch() {
    ...
}

    #[test]
    fn test_sandbox_enabled() {
    ...
}

    #[test]
    fn test_worktree_branch() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_worktree_branch() {
    ...
}

    #[test]
    fn test_sandbox_image() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_sandbox_image() {
    ...
}

    #[test]
    fn test_sandbox_enabled_serde_compat() {
    ...
}

    #[test]
    fn test_channel_binding() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_active_session() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_list_channel_sessions() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_channel_binding() {
    ...
}

    #[test]
    fn test_mcp_disabled() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_mcp_disabled() {
    ...
}

    #[tokio::test]
    async fn test_version_starts_at_zero() {
    ...
}

    #[tokio::test]
    async fn test_version_increments_on_mutation() {
    ...
}

    #[tokio::test]
    async fn test_version_increments_on_upsert_update() {
    ...
}

    #[tokio::test]
    async fn test_version_in_list() {
    ...
}

    #[test]
    fn test_json_backend_version() {
    ...
}

    #[test]
    fn test_agent_id() {
    ...
}

    #[test]
    fn test_list_by_agent_id() {
    ...
}

    #[test]
    fn test_delete_by_agent_id() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_agent_id() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_list_by_agent_id() {
    ...
}

    #[tokio::test]
    async fn test_sqlite_delete_by_agent_id() {
    ...
}

    #[test]
    fn test_agent_id_serde_compat() {
    ...
}
}
