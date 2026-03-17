//! Configuration validation engine.
//!
//! Validates TOML configuration files against the known schema, detects
//! unknown/misspelled fields, and reports security warnings.

use std::{collections::HashMap, path::Path};

use crate::schema::MoltisConfig;

/// Severity level for a diagnostic.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    ...
}

impl std::fmt::Display for Severity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// A single validation diagnostic.
#[derive(Debug, Clone)]
pub struct Diagnostic {
    ...
}

/// Result of validating a configuration file.
#[derive(Debug, Clone)]
pub struct ValidationResult {
    ...
}

impl ValidationResult {
    /// Returns `true` if any diagnostic is an error.
    #[must_use]
    pub fn has_errors(&self) -> bool {

    /// Count diagnostics by severity.
    #[must_use]
    pub fn count(&self, severity: Severity) -> usize {
    ...
}
}

// ── Schema tree for unknown-field detection ─────────────────────────────────

/// Represents the expected shape of the configuration schema.
enum KnownKeys {
    ...
}

/// Known LLM provider names for hint diagnostics.
const KNOWN_PROVIDER_NAMES: &[&str] = &[
    "anthropic",
    "openai",
    "gemini",
    "groq",
    "xai",
    "deepseek",
    "mistral",
    "openrouter",
    "cerebras",
    "minimax",
    "moonshot",
    "venice",
    "ollama",
    "lmstudio",
];

/// Static metadata keys allowed directly under `[providers]`.
const PROVIDERS_META_KEYS: &[&str] = &["offered"];

/// Build the full schema map mirroring every field in `schema.rs`.
fn build_schema_map() -> KnownKeys {
    ...
}

// ── Levenshtein distance ────────────────────────────────────────────────────

/// Compute the Levenshtein edit distance between two strings.
fn levenshtein(a: &str, b: &str) -> usize {
    ...
}

/// Find the best match for `needle` among `candidates` using Levenshtein
/// distance. Returns `Some(best)` if the distance is <= `max_distance`.
fn suggest<'a>(needle: &str, candidates: &[&'a str], max_distance: usize) -> Option<&'a str> {
    let mut best: Option<(&'a str, usize)> = None;
    for &candidate in candidates {
        let d = levenshtein(needle, candidate);
        if d > 0 && d <= max_distance && best.as_ref().is_none_or(|(_, bd)| d < *bd) {
            best = Some((candidate, d));
        }
    }
    best.map(|(s, _)| s)
}

// ── Core validation ─────────────────────────────────────────────────────────

/// Validate a config file at the given path, or discover the default config
/// file location if `path` is `None`.
#[must_use]
pub fn validate(path: Option<&Path>) -> ValidationResult {
    ...
}

/// Validate a TOML string without file-system side effects (useful for tests
/// and the gateway).
#[must_use]
pub fn validate_toml_str(toml_str: &str) -> ValidationResult {
    ...
}

fn check_deprecated_fields(
    toml_value: &toml::Value,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<&'static str> {
    ...
}

fn should_suppress_deprecated_conflict_type_error(
    message: &str,
    conflicting_replacements: &[&str],
) -> bool {
    ...
}

fn check_deprecated_memory_field(
    memory: &toml::map::Map<String, toml::Value>,
    legacy: &str,
    replacement: &str,
    diagnostics: &mut Vec<Diagnostic>,
) -> bool {
    ...
}

fn check_deprecated_ignored_memory_field(
    memory: &toml::map::Map<String, toml::Value>,
    legacy: &str,
    message: &str,
    diagnostics: &mut Vec<Diagnostic>,
) {
    ...
}

/// Walk the TOML value tree against the schema tree and flag unknown keys.
fn check_unknown_fields(
    value: &toml::Value,
    schema: &KnownKeys,
    prefix: &str,
    diagnostics: &mut Vec<Diagnostic>,
) {
    ...
}

/// Check provider names under `[providers]` and warn about unknown ones.
fn check_provider_names(
    providers: &toml::map::Map<String, toml::Value>,
    diagnostics: &mut Vec<Diagnostic>,
) {
    ...
}

/// Run semantic checks on a successfully parsed config.
fn check_semantic_warnings(config: &MoltisConfig, diagnostics: &mut Vec<Diagnostic>) {
    ...
}

/// Check that file paths referenced in TLS config exist on disk.
fn check_file_references(toml_str: &str, _config_path: &Path, diagnostics: &mut Vec<Diagnostic>) {
    ...
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn levenshtein_empty() {
    ...
}

    #[test]
    fn levenshtein_single_edit() {
    ...
}

    #[test]
    fn levenshtein_substitution() {
    ...
}

    #[test]
    fn levenshtein_insertion() {
    ...
}

    #[test]
    fn unknown_top_level_key_with_suggestion() {
    ...
}

    #[test]
    fn unknown_nested_key_with_suggestion() {
    ...
}

    #[test]
    fn unknown_field_inside_provider_entry() {
    ...
}

    #[test]
    fn misspelled_provider_name_warned_with_suggestion() {
    ...
}

    #[test]
    fn providers_offered_key_not_treated_as_provider_name() {
    ...
}

    #[test]
    fn custom_provider_name_warned_without_close_match() {
    ...
}

    #[test]
    fn empty_config_is_valid() {
    ...
}

    #[test]
    fn full_valid_config_no_diagnostics() {
    ...
}

    #[test]
    fn syntax_error_detected() {
    ...
}

    #[test]
    fn auth_disabled_non_localhost_warned() {
    ...
}

    #[test]
    fn auth_disabled_localhost_not_warned() {
    ...
}

    #[test]
    fn tls_cert_without_key_is_error() {
    ...
}

    #[test]
    fn tls_key_without_cert_is_error() {
    ...
}

    #[test]
    fn unknown_tailscale_mode_warned() {
    ...
}

    #[test]
    fn sandbox_mode_off_warned() {
    ...
}

    #[test]
    fn port_zero_info() {
    ...
}

    #[test]
    fn unknown_memory_backend_warned() {
    ...
}

    #[test]
    fn unknown_memory_provider_warned() {
    ...
}

    #[test]
    fn memory_disable_rag_is_valid_field() {
    ...
}

    #[test]
    fn legacy_memory_embedding_fields_warn_but_do_not_error() {
    ...
}

    #[test]
    fn conflicting_legacy_and_modern_memory_field_reports_targeted_error() {
    ...
}

    #[test]
    fn duplicate_field_suppression_matches_only_conflicting_replacements() {
    ...
}

    #[test]
    fn unknown_sandbox_backend_warned() {
    ...
}

    #[test]
    fn podman_sandbox_backend_accepted() {
    ...
}

    #[test]
    fn unknown_security_level_warned() {
    ...
}

    #[test]
    fn unknown_voice_tts_list_provider_warned() {
    ...
}

    #[test]
    fn unknown_voice_stt_list_provider_warned() {
    ...
}

    #[test]
    fn known_voice_provider_list_entries_not_warned() {
    ...
}

    #[test]
    fn tls_disabled_non_localhost_warned() {
    ...
}

    #[test]
    fn mcp_server_entries_validated() {
    ...
}

    #[test]
    fn hooks_array_entries_validated() {
    ...
}

    /// Schema drift guard: verify every key from `MoltisConfig::default()` is
    /// represented in `build_schema_map()`.
    #[test]
    fn schema_drift_guard() {
    ...
}

    /// Helper for schema drift guard: recursively collect keys in `value` that
    /// are not present in `schema`.
    fn collect_missing_keys(
        value: &toml::Value,
        schema: &KnownKeys,
        prefix: &str,
        missing: &mut Vec<String>,
    ) {
    ...
}

    #[test]
    fn suggest_finds_close_match() {
    ...
}

    #[test]
    fn suggest_returns_none_for_distant() {
    ...
}

    #[test]
    fn valid_known_providers_not_warned() {
    ...
}

    #[test]
    fn env_section_passes_validation() {
    ...
}

    #[test]
    fn custom_provider_prefix_suppresses_unknown_provider_warning() {
    ...
}

    #[test]
    fn non_custom_unknown_provider_still_warns() {
    ...
}

    #[test]
    fn tools_agent_max_iterations_must_be_positive() {
    ...
}

    #[test]
    fn channels_offered_accepted_without_warning() {
    ...
}

    #[test]
    fn channels_offered_discord_accepted() {
    ...
}

    #[test]
    fn channels_discord_config_accepted() {
    ...
}

    #[test]
    fn channels_offered_unknown_type_warned() {
    ...
}

    #[test]
    fn channels_offered_slack_accepted() {
    ...
}

    #[test]
    fn channels_offered_dynamic_type_accepted() {
    ...
}

    #[test]
    fn channels_extra_config_accepted() {
    ...
}

    #[test]
    fn tool_mode_field_accepted_in_provider_entry() {
    ...
}

    #[test]
    fn url_field_accepted_in_provider_entry() {
    ...
}

    #[test]
    fn tool_mode_all_values_parse_correctly() {
    ...
}

    #[test]
    fn reasoning_effort_valid_values_no_error() {
    ...
}

    #[test]
    fn reasoning_effort_invalid_value_reports_type_error() {
    ...
}

    #[test]
    fn reasoning_effort_recognized_in_schema() {
    ...
}
}
