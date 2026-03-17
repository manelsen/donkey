//! `moltis doctor` — health check, config validation, and environment audit.
//!
//! Runs a series of checks against the local installation and prints a
//! structured report with `[ok]`, `[warn]`, `[fail]`, `[skip]`, or `[info]`
//! status indicators per item.

use std::path::{Path, PathBuf};

use {
    anyhow::Result,
    moltis_config::{
        MoltisConfig,
        validate::{self, Severity},
    },
    secrecy::ExposeSecret,
};

// ── ANSI helpers ────────────────────────────────────────────────────────────

const GREEN: &str = "\x1b[32m";
const RED: &str = "\x1b[31m";
const YELLOW: &str = "\x1b[33m";
const CYAN: &str = "\x1b[36m";
const DIM: &str = "\x1b[2m";
const BOLD: &str = "\x1b[1m";
const RESET: &str = "\x1b[0m";

/// Per-check result used to build the report.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Status {
    ...
}

impl Status {
    fn label(self) -> &'static str {

    fn color(self) -> &'static str {
    ...
}
}

struct CheckItem {
    ...
}

struct Section {
    ...
}

impl Section {
    fn new(title: impl Into<String>) -> Self {

    fn push(&mut self, status: Status, message: impl Into<String>) {
    ...
}
}

// ── Printing ────────────────────────────────────────────────────────────────

fn print_report(sections: &[Section]) -> (usize, usize) {
    ...
}

// ── Provider → env var mapping ──────────────────────────────────────────────

/// (provider_name, env_var, is_key_optional)
const PROVIDER_ENV_MAP: &[(&str, &str, bool)] = &[
    ("anthropic", "ANTHROPIC_API_KEY", false),
    ("openai", "OPENAI_API_KEY", false),
    ("gemini", "GEMINI_API_KEY", false),
    ("groq", "GROQ_API_KEY", false),
    ("xai", "XAI_API_KEY", false),
    ("deepseek", "DEEPSEEK_API_KEY", false),
    ("mistral", "MISTRAL_API_KEY", false),
    ("openrouter", "OPENROUTER_API_KEY", false),
    ("cerebras", "CEREBRAS_API_KEY", false),
    ("minimax", "MINIMAX_API_KEY", false),
    ("moonshot", "MOONSHOT_API_KEY", false),
    ("venice", "VENICE_API_KEY", false),
    ("ollama", "OLLAMA_API_KEY", true),
    ("kimi-code", "KIMI_API_KEY", false),
];

/// OAuth providers that don't use env var API keys.
const OAUTH_PROVIDERS: &[&str] = &["openai-codex", "github-copilot"];

// ── Entry point ─────────────────────────────────────────────────────────────

pub async fn handle_doctor() -> Result<()> {
    ...
}

// ── 1. Config validation ────────────────────────────────────────────────────

fn check_config(config_dir: Option<&Path>) -> Section {
    ...
}

fn config_validation_status(diagnostic: &moltis_config::Diagnostic) -> Option<Status> {
    ...
}

// ── 2. Security audit ───────────────────────────────────────────────────────

fn check_security(config: &MoltisConfig, config_dir: Option<&Path>, data_dir: &Path) -> Section {
    ...
}

// ── 3. Directory health ─────────────────────────────────────────────────────

fn check_directories(config_dir: Option<&Path>, data_dir: &Path) -> Section {
    ...
}

fn check_writable(section: &mut Section, dir: &Path, label: &str) {
    ...
}

// ── 4. Database health ──────────────────────────────────────────────────────

async fn check_database(data_dir: &Path) -> Section {
    ...
}

// ── 5. Provider readiness ───────────────────────────────────────────────────

fn check_providers(config: &MoltisConfig) -> Section {
    ...
}

// ── 6. TLS health ───────────────────────────────────────────────────────────

#[cfg(feature = "tls")]
fn check_tls(config: &MoltisConfig) -> Section {
    ...
}

#[cfg(feature = "tls")]
fn check_file_readable(section: &mut Section, path: &str, label: &str) {
    ...
}

/// Returns the age of a file in days (from mtime), or `None` on error.
#[cfg(feature = "tls")]
fn cert_age_days(path: &Path) -> Option<i64> {
    ...
}

// ── 7. MCP server health ───────────────────────────────────────────────────

fn check_mcp_servers(config: &MoltisConfig) -> Section {
    ...
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn status_labels() {
    ...
}

    #[test]
    fn section_push_counts() {
    ...
}

    #[test]
    fn print_report_counts_errors_and_warnings() {
    ...
}

    #[test]
    fn config_validation_status_warns_for_deprecated_field() {
    ...
}

    #[test]
    fn check_providers_empty_config() {
    ...
}

    #[test]
    fn check_providers_with_config_key() {
    ...
}

    #[test]
    fn check_providers_missing_key_warns() {
    ...
}

    #[test]
    fn check_providers_ollama_optional() {
    ...
}

    #[test]
    fn check_providers_disabled_skipped() {
    ...
}

    #[test]
    fn check_providers_oauth_skipped() {
    ...
}

    #[test]
    fn check_mcp_servers_empty() {
    ...
}

    #[test]
    fn check_mcp_servers_disabled_skipped() {
    ...
}

    #[test]
    fn check_mcp_servers_missing_command_fails() {
    ...
}

    #[test]
    fn check_mcp_servers_sse_with_url_ok() {
    ...
}

    #[test]
    fn check_mcp_servers_sse_without_url_fails() {
    ...
}

    #[test]
    fn check_mcp_servers_nonexistent_command_fails() {
    ...
}

    #[test]
    fn check_directories_with_temp_dirs() {
    ...
}

    #[test]
    fn check_directories_missing_config_dir() {
    ...
}

    #[tokio::test]
    async fn check_database_missing_file() {
    ...
}

    #[tokio::test]
    async fn check_database_valid_db() {
    ...
}

    #[test]
    fn check_security_no_api_keys_in_config() {
    ...
}

    #[test]
    fn check_security_api_keys_in_config_warns() {
    ...
}
}
