//! Agent persona store for multi-agent support.
//!
//! Each agent has its own workspace directory under `data_dir()/agents/<id>/`
//! with dedicated `IDENTITY.md`, `SOUL.md`, and memory files.
//! The "main" agent uses `data_dir()/agents/main` with fallback reads from the
//! root workspace for backward compatibility.

use {
    serde::{Deserialize, Serialize},
    std::{
        path::{Path, PathBuf},
        time::{SystemTime, UNIX_EPOCH},
    },
};

/// Errors from agent persona operations.
#[derive(Debug, thiserror::Error)]
pub enum AgentError {
    ...
}

impl From<AgentError> for moltis_protocol::ErrorShape {
    fn from(err: AgentError) -> Self {
}

type Result<T> = std::result::Result<T, AgentError>;

fn now_ms() -> i64 {
    ...
}

/// A persisted agent persona.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentPersona {
    ...
}

/// Parameters for creating a new agent.
#[derive(Debug, Deserialize)]
pub struct CreateAgentParams {
    ...
}

/// Parameters for updating an existing agent.
#[derive(Debug, Deserialize)]
pub struct UpdateAgentParams {
    ...
}

#[derive(sqlx::FromRow)]
struct AgentRow {
    ...
}

impl From<AgentRow> for AgentPersona {
    fn from(r: AgentRow) -> Self {
}

/// Validate an agent ID: lowercase alphanumeric + hyphens, 1-50 chars, not "main".
pub fn validate_agent_id(id: &str) -> Result<()> {
    ...
}

/// SQLite-backed agent persona store.
pub struct AgentPersonaStore {
    ...
}

impl AgentPersonaStore {
    pub fn new(pool: sqlx::SqlitePool) -> Self {

    /// Return the current default agent ID.
    ///
    /// If no explicit default row is set, this falls back to `"main"`.
    pub async fn default_id(&self) -> Result<String> {
    ...
}

    /// Set the default agent ID. `"main"` is always valid.
    pub async fn set_default(&self, id: &str) -> Result<String> {
    ...
}

    /// Ensure the default main workspace exists and is seeded from the root
    /// workspace when files are present there.
    pub fn ensure_main_workspace_seeded(&self) -> Result<PathBuf> {
    ...
}

    /// List all agents: synthesize "main" from config, then append DB rows.
    pub async fn list(&self) -> Result<Vec<AgentPersona>> {
    ...
}

    /// Get a single agent by ID.
    pub async fn get(&self, id: &str) -> Result<Option<AgentPersona>> {
    ...
}

    /// Create a new agent persona and its workspace directory.
    pub async fn create(&self, params: CreateAgentParams) -> Result<AgentPersona> {
    ...
}

    /// Update an existing agent persona.
    pub async fn update(&self, id: &str, params: UpdateAgentParams) -> Result<AgentPersona> {
    ...
}

    /// Delete an agent persona. Cannot delete "main".
    pub async fn delete(&self, id: &str) -> Result<()> {
    ...
}

    /// Create the workspace directory for an agent.
    pub fn ensure_workspace(&self, agent_id: &str) -> Result<PathBuf> {
    ...
}
}

/// Synthesize the "main" agent persona from the global identity config.
fn synthesize_main_agent(is_default: bool) -> AgentPersona {
    ...
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    async fn test_pool() -> sqlx::SqlitePool {
    ...
}

    #[tokio::test]
    async fn test_list_includes_main() {
    ...
}

    #[tokio::test]
    async fn test_create_and_get() {
    ...
}

    #[tokio::test]
    async fn test_create_rejects_main() {
    ...
}

    #[tokio::test]
    async fn test_create_rejects_invalid_id() {
    ...
}

    #[tokio::test]
    async fn test_update() {
    ...
}

    #[tokio::test]
    async fn test_update_main_rejected() {
    ...
}

    #[tokio::test]
    async fn test_delete() {
    ...
}

    #[tokio::test]
    async fn test_delete_main_rejected() {
    ...
}

    #[tokio::test]
    async fn test_set_default_non_main() {
    ...
}

    #[tokio::test]
    async fn test_delete_default_rejected() {
    ...
}

    #[tokio::test]
    async fn test_delete_nonexistent() {
    ...
}

    #[tokio::test]
    async fn test_list_order() {
    ...
}

    #[tokio::test]
    async fn test_get_main() {
    ...
}
}
