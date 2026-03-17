use std::{
    fs,
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

use {
    crate::{Result, types::Project},
    async_trait::async_trait,
};

fn now_ms() -> u64 {
    ...
}

/// Trait for persisting projects. Implementations can be TOML-file-backed,
/// SQLite, etc.
#[async_trait]
pub trait ProjectStore: Send + Sync {
    async fn list(&self) -> Result<Vec<Project>>;
    async fn get(&self, id: &str) -> Result<Option<Project>>;
    async fn upsert(&self, project: Project) -> Result<()>;
    async fn delete(&self, id: &str) -> Result<()>;
}

// ── TOML file-backed implementation ──────────────────────────────────

#[derive(Debug, serde::Serialize, serde::Deserialize, Default)]
struct TomlFile {
    ...
}

/// Stores projects in a TOML file at the given path.
pub struct TomlProjectStore {
    ...
}

impl TomlProjectStore {
    pub fn new(path: PathBuf) -> Self {

    fn read_file(&self) -> Result<TomlFile> {
    ...
}

    fn write_file(&self, file: &TomlFile) -> Result<()> {
    ...
}
}

#[async_trait]
impl ProjectStore for TomlProjectStore {
    async fn list(&self) -> Result<Vec<Project>> {

    async fn get(&self, id: &str) -> Result<Option<Project>> {
    ...
}

    async fn upsert(&self, project: Project) -> Result<()> {
    ...
}

    async fn delete(&self, id: &str) -> Result<()> {
    ...
}
}

// ── SQLite-backed implementation ────────────────────────────────────

/// Stores projects in a SQLite database.
pub struct SqliteProjectStore {
    ...
}

impl SqliteProjectStore {
    pub fn new(pool: sqlx::SqlitePool) -> Self {

    /// Initialize the projects table schema.
    ///
    /// **Deprecated**: Schema is now managed by sqlx migrations in the gateway crate.
    /// This method is retained for tests that use in-memory databases.
    #[doc(hidden)]
    pub async fn init(pool: &sqlx::SqlitePool) -> Result<()> {
    ...
}
}

#[async_trait]
impl ProjectStore for SqliteProjectStore {
    async fn list(&self) -> Result<Vec<Project>> {

    async fn get(&self, id: &str) -> Result<Option<Project>> {
    ...
}

    async fn upsert(&self, project: Project) -> Result<()> {
    ...
}

    async fn delete(&self, id: &str) -> Result<()> {
    ...
}
}

/// Internal row type for sqlx mapping.
#[derive(sqlx::FromRow)]
struct ProjectRow {
    ...
}

impl From<ProjectRow> for Project {
    fn from(r: ProjectRow) -> Self {
}

/// Create a new project with auto-derived fields.
pub fn new_project(id: String, label: String, directory: PathBuf) -> Project {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    async fn sqlite_pool() -> sqlx::SqlitePool {
    ...
}

    #[tokio::test]
    async fn test_sqlite_store_crud() {
    ...
}

    #[tokio::test]
    async fn test_toml_store_persistence() {
    ...
}
}
