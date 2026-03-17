//! Browser action types and request/response structures.

use std::fmt;

use serde::{Deserialize, Serialize};

/// Browser action to perform.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum BrowserAction {
    ...
}

fn default_wait_timeout_ms() -> u64 {
    ...
}

/// Known Chromium-family browser engines we can launch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BrowserKind {
    ...
}

impl BrowserKind {
    pub fn as_str(self) -> &'static str {
}

impl fmt::Display for BrowserKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
}

/// Preferred browser for a request.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum BrowserPreference {
    ...
}

impl BrowserPreference {
    pub fn preferred_kind(self) -> Option<BrowserKind> {
}

impl fmt::Display for BrowserPreference {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
}

impl fmt::Display for BrowserAction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
}

/// Request to the browser service.
#[derive(Debug, Clone, Deserialize)]
pub struct BrowserRequest {
    ...
}

fn default_timeout_ms() -> u64 {
    ...
}

/// Element reference in a DOM snapshot.
#[derive(Debug, Clone, Serialize)]
pub struct ElementRef {
    ...
}

/// Bounding box for an element.
#[derive(Debug, Clone, Serialize)]
pub struct ElementBounds {
    ...
}

/// DOM snapshot with element references.
#[derive(Debug, Clone, Serialize)]
pub struct DomSnapshot {
    ...
}

/// Viewport size.
#[derive(Debug, Clone, Serialize)]
pub struct ViewportSize {
    ...
}

/// Scroll dimensions.
#[derive(Debug, Clone, Serialize)]
pub struct ScrollDimensions {
    ...
}

/// Response from a browser action.
#[derive(Debug, Clone, Serialize)]
pub struct BrowserResponse {
    ...
}

impl BrowserResponse {
    pub fn success(session_id: String, duration_ms: u64, sandboxed: bool) -> Self {

    pub fn error(session_id: String, error: impl Into<String>, duration_ms: u64) -> Self {
    ...
}

    pub fn with_screenshot(mut self, screenshot: String, scale: f64) -> Self {
    ...
}

    pub fn with_snapshot(mut self, snapshot: DomSnapshot) -> Self {
    ...
}

    pub fn with_result(mut self, result: serde_json::Value) -> Self {
    ...
}

    pub fn with_url(mut self, url: String) -> Self {
    ...
}

    pub fn with_title(mut self, title: String) -> Self {
    ...
}
}

/// Browser configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct BrowserConfig {
    ...
}

fn default_sandbox_image() -> String {
    ...
}

fn default_container_prefix() -> String {
    ...
}

impl Default for BrowserConfig {
    fn default() -> Self {
}

impl BrowserConfig {
    /// Resolve the effective Chrome profile directory, if profile persistence is enabled.
    ///
    /// Returns `Some(path)` when either `profile_dir` is set or `persist_profile` is true.
    /// Returns `None` when profiles should be ephemeral.
    #[must_use]
    pub fn resolved_profile_dir(&self) -> Option<std::path::PathBuf> {
}

impl From<&moltis_config::schema::BrowserConfig> for BrowserConfig {
    fn from(cfg: &moltis_config::schema::BrowserConfig) -> Self {
}

/// Check if a URL is allowed based on the allowed domains list.
/// Returns true if allowed, false if blocked.
pub fn is_domain_allowed(url: &str, allowed_domains: &[String]) -> bool {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_domain_allowed_exact_match() {
    ...
}

    #[test]
    fn test_domain_allowed_wildcard() {
    ...
}

    #[test]
    fn test_domain_allowed_multiple() {
    ...
}

    #[test]
    fn test_domain_allowed_invalid_url() {
    ...
}

    #[test]
    fn test_browser_preference_default_is_auto() {
    ...
}

    #[test]
    fn test_browser_preference_deserialize() {
    ...
}

    #[test]
    fn resolved_profile_dir_returns_path_by_default() {
    ...
}

    #[test]
    fn resolved_profile_dir_returns_none_when_disabled() {
    ...
}

    #[test]
    fn resolved_profile_dir_uses_custom_path() {
    ...
}

    #[test]
    fn resolved_profile_dir_custom_overrides_persist_flag() {
    ...
}
}
