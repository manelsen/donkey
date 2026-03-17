//! Per-session key-value state store.
//!
//! Provides a SQLite-backed KV store scoped to `(session_key, namespace, key)`
//! so that skills and extensions can persist context across messages.

use std::time::{SystemTime, UNIX_EPOCH};

use crate::Result;

/// A single state entry.
#[derive(Debug, Clone)]
pub struct StateEntry {
    ...
}

#[derive(sqlx::FromRow)]
struct StateRow {
    ...
}

impl From<StateRow> for StateEntry {
    fn from(r: StateRow) -> Self {
}

/// SQLite-backed per-session state store.
pub struct SessionStateStore {
    ...
}

fn now_ms() -> i64 {
    ...
}

impl SessionStateStore {
    pub fn new(pool: sqlx::SqlitePool) -> Self {

    /// Get a value by session key, namespace, and key.
    pub async fn get(
        &self,
        session_key: &str,
        namespace: &str,
        key: &str,
    ) -> Result<Option<String>> {
    ...
}

    /// Set a value. Inserts or updates the entry.
    pub async fn set(
        &self,
        session_key: &str,
        namespace: &str,
        key: &str,
        value: &str,
    ) -> Result<()> {
    ...
}

    /// Delete a single key.
    pub async fn delete(&self, session_key: &str, namespace: &str, key: &str) -> Result<bool> {
    ...
}

    /// List all entries in a namespace for a session.
    pub async fn list(&self, session_key: &str, namespace: &str) -> Result<Vec<StateEntry>> {
    ...
}

    /// Delete all entries in a namespace for a session.
    pub async fn delete_all(&self, session_key: &str, namespace: &str) -> Result<u64> {
    ...
}

    /// Delete all state for a session (cascade on session delete).
    pub async fn delete_session(&self, session_key: &str) -> Result<u64> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_set_and_get() {
    ...
}

    #[tokio::test]
    async fn test_get_missing() {
    ...
}

    #[tokio::test]
    async fn test_set_overwrites() {
    ...
}

    #[tokio::test]
    async fn test_delete() {
    ...
}

    #[tokio::test]
    async fn test_delete_missing() {
    ...
}

    #[tokio::test]
    async fn test_list() {
    ...
}

    #[tokio::test]
    async fn test_delete_all() {
    ...
}

    #[tokio::test]
    async fn test_delete_session() {
    ...
}

    #[tokio::test]
    async fn test_namespace_isolation() {
    ...
}
}
