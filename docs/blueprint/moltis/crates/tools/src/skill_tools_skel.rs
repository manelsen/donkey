//! Agent tools for creating, updating, and deleting personal skills at runtime.
//! Skills are written to `<data_dir>/skills/<name>/SKILL.md` (Personal source).

use std::path::{Path, PathBuf};

use {
    async_trait::async_trait,
    moltis_agents::tool_registry::AgentTool,
    serde_json::{Value, json},
};

use crate::error::Error;

/// Tool that creates a new personal skill in `<data_dir>/skills/`.
pub struct CreateSkillTool {
    ...
}

impl CreateSkillTool {
    pub fn new(data_dir: PathBuf) -> Self {

    fn skills_dir(&self) -> PathBuf {
    ...
}
}

#[async_trait]
impl AgentTool for CreateSkillTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

/// Tool that updates an existing personal skill in `<data_dir>/skills/`.
pub struct UpdateSkillTool {
    ...
}

impl UpdateSkillTool {
    pub fn new(data_dir: PathBuf) -> Self {

    fn skills_dir(&self) -> PathBuf {
    ...
}
}

#[async_trait]
impl AgentTool for UpdateSkillTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

/// Tool that deletes a personal skill from `<data_dir>/skills/`.
pub struct DeleteSkillTool {
    ...
}

impl DeleteSkillTool {
    pub fn new(data_dir: PathBuf) -> Self {

    fn skills_dir(&self) -> PathBuf {
    ...
}
}

#[async_trait]
impl AgentTool for DeleteSkillTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

fn build_skill_md(name: &str, description: &str, body: &str, allowed_tools: &[String]) -> String {
    ...
}

async fn write_skill(skill_dir: &Path, content: &str) -> crate::Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_create_with_allowed_tools() {
    ...
}

    #[tokio::test]
    async fn test_create_invalid_name() {
    ...
}

    #[tokio::test]
    async fn test_create_duplicate_fails() {
    ...
}

    #[tokio::test]
    async fn test_update_skill() {
    ...
}

    #[tokio::test]
    async fn test_update_nonexistent_fails() {
    ...
}

    #[tokio::test]
    async fn test_delete_skill() {
    ...
}

    #[tokio::test]
    async fn test_delete_nonexistent_fails() {
    ...
}
}
