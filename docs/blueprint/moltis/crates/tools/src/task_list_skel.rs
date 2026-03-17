//! Shared task list tool for inter-agent task coordination.

use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use {
    async_trait::async_trait,
    serde::{Deserialize, Serialize},
    tokio::sync::RwLock,
};

use {
    crate::{
        Error,
        params::{require_str, str_param, str_param_any},
    },
    moltis_agents::tool_registry::AgentTool,
};

/// Status of a task in the shared list.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    ...
}

impl TaskStatus {
    fn as_str(&self) -> &'static str {
}

impl std::str::FromStr for TaskStatus {
    type Err = Error;

    fn from_str(input: &str) -> crate::Result<Self> {
}

/// A single task in the shared list.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    ...
}

/// File-backed store for one logical task list.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskList {
    ...
}

impl Default for TaskList {
    fn default() -> Self {
}

/// Thread-safe, file-backed task store.
pub struct TaskStore {
    ...
}

impl TaskStore {
    pub fn new(base_dir: &Path) -> Self {

    fn file_path(&self, list_id: &str) -> PathBuf {
    ...
}

    async fn ensure_list(&self, list_id: &str) -> crate::Result<()> {
    ...
}

    async fn persist(&self, list_id: &str) -> crate::Result<()> {
    ...
}

    fn now() -> u64 {
    ...
}

    pub async fn create(
        &self,
        list_id: &str,
        subject: String,
        description: String,
    ) -> crate::Result<Task> {
    ...
}

    pub async fn list_tasks(
        &self,
        list_id: &str,
        status_filter: Option<&TaskStatus>,
    ) -> crate::Result<Vec<Task>> {
    ...
}

    pub async fn get(&self, list_id: &str, task_id: &str) -> crate::Result<Option<Task>> {
    ...
}

    pub async fn update(
        &self,
        list_id: &str,
        task_id: &str,
        status: Option<TaskStatus>,
        subject: Option<String>,
        description: Option<String>,
        owner: Option<String>,
        blocked_by: Option<Vec<String>>,
    ) -> crate::Result<Task> {
    ...
}

    /// Atomically claim a pending task and set it to in-progress.
    pub async fn claim(&self, list_id: &str, task_id: &str, owner: &str) -> crate::Result<Task> {
    ...
}
}

/// Tool wrapper around [`TaskStore`].
pub struct TaskListTool {
    ...
}

impl TaskListTool {
    pub fn new(base_dir: &Path) -> Self {
}

#[async_trait]
impl AgentTool for TaskListTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn create_and_list_tasks() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn claim_moves_task_to_in_progress() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn claim_rejects_non_pending_task() -> TestResult<()> {
    ...
}

    #[tokio::test]
    async fn claim_rejects_when_blocked_dependencies_incomplete() -> TestResult<()> {
    ...
}
}
