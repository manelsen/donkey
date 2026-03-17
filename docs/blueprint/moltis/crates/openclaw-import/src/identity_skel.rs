//! Import user/agent identity from OpenClaw config.

use std::{
    collections::HashMap,
    path::{Path, PathBuf},
};

use tracing::{debug, info};

use crate::{
    detect::{OpenClawDetection, resolve_agent_sessions_dir},
    report::{CategoryReport, ImportCategory},
    types::{OpenClawAssistantConfig, OpenClawConfig, OpenClawSessionIndexEntry},
};

/// Extracted identity from an OpenClaw installation.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct ImportedIdentity {
    ...
}

/// Import identity data from OpenClaw.
pub fn import_identity(detection: &OpenClawDetection) -> (CategoryReport, ImportedIdentity) {
    ...
}

pub(crate) fn load_config(home_dir: &Path) -> OpenClawConfig {
    ...
}

fn infer_agent_name_from_workspace(
    config: &OpenClawConfig,
    detection: &OpenClawDetection,
) -> Option<String> {
    ...
}

fn infer_theme(config: &OpenClawConfig, detection: &OpenClawDetection) -> Option<String> {
    ...
}

fn extract_theme_from_assistant(assistant: Option<&OpenClawAssistantConfig>) -> Option<String> {
    ...
}

fn infer_theme_from_workspace_identity(
    config: &OpenClawConfig,
    detection: &OpenClawDetection,
) -> Option<String> {
    ...
}

pub(crate) fn compose_theme(creature: Option<String>, vibe: Option<String>) -> Option<String> {
    ...
}

fn normalize_identity_value(value: Option<&str>) -> Option<String> {
    ...
}

fn is_placeholder_value(value: &str) -> bool {
    ...
}

fn extract_yaml_frontmatter(content: &str) -> Option<&str> {
    ...
}

#[derive(Default)]
pub(crate) struct WorkspaceIdentityFrontmatter {
    ...
}

fn parse_identity_frontmatter(frontmatter: &str) -> WorkspaceIdentityFrontmatter {
    ...
}

fn unquote_yaml_scalar(value: &str) -> &str {
    ...
}

pub(crate) fn parse_workspace_identity(content: &str) -> WorkspaceIdentityFrontmatter {
    ...
}

fn normalize_markdown_key_value_line(raw_line: &str) -> &str {
    ...
}

fn strip_leading_html_comments(content: &str) -> &str {
    ...
}

fn candidate_workspace_dirs(
    config: &OpenClawConfig,
    detection: &OpenClawDetection,
) -> Vec<PathBuf> {
    ...
}

fn resolve_workspace_path(raw: &str, home_dir: &Path) -> PathBuf {
    ...
}

fn workspace_basename(workspace: &Path) -> Option<String> {
    ...
}

fn infer_user_name_from_sessions_index(detection: &OpenClawDetection) -> Option<String> {
    ...
}

fn preferred_agent_id(detection: &OpenClawDetection) -> Option<&str> {
    ...
}

pub(crate) fn normalize_display_name(label: &str) -> Option<String> {
    ...
}

fn titleize_identifier(raw: &str) -> String {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn import_agent_name_from_ui() {
    ...
}

    #[test]
    fn import_agent_name_from_agents_list() {
    ...
}

    #[test]
    fn import_theme_from_ui_assistant_theme() {
    ...
}

    #[test]
    fn import_theme_from_ui_assistant_creature_and_vibe() {
    ...
}

    #[test]
    fn import_theme_from_workspace_identity_frontmatter() {
    ...
}

    #[test]
    fn import_theme_from_workspace_identity_markdown_template() {
    ...
}

    #[test]
    fn import_theme_falls_back_to_detected_workspace_when_config_workspace_missing() {
    ...
}

    #[test]
    fn import_theme_resolves_workspace_basename_under_openclaw_home() {
    ...
}

    #[test]
    fn import_timezone() {
    ...
}

    #[test]
    fn import_user_name() {
    ...
}

    #[test]
    fn import_user_name_from_sessions_index() {
    ...
}

    #[test]
    fn import_agent_name_from_workspace_basename() {
    ...
}

    #[test]
    fn no_config_returns_skipped() {
    ...
}
}
