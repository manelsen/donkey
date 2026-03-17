#![allow(clippy::unwrap_used, clippy::expect_used)]
fn main() {
    ...
}

// ── Config parsing ──────────────────────────────────────────────────────────

/// Benchmark generating the default TOML config template.
#[divan::bench]
fn config_template_generation() -> String {
    ...
}

/// Benchmark constructing a `MoltisConfig` with all defaults.
#[divan::bench]
fn config_default_construction() -> moltis_config::MoltisConfig {
    ...
}

/// Benchmark loading + parsing a TOML config from disk (the full boot path).
#[divan::bench]
fn config_load_toml(bencher: divan::Bencher) {
    ...
}

/// Benchmark config round-trip: serialize MoltisConfig to TOML, then deserialize.
#[divan::bench]
fn config_serde_roundtrip() {
    ...
}

/// Benchmark validating a TOML config string (schema checks, semantic warnings).
#[divan::bench]
fn config_validate_toml(bencher: divan::Bencher) {
    ...
}

// ── Provider model lookups ──────────────────────────────────────────────────

const MODEL_IDS: &[&str] = &[
    "claude-sonnet-4-5-20250929",
    "gpt-4o",
    "gpt-5",
    "gemini-2.0-flash",
    "codestral-latest",
    "mistral-large-latest",
    "o3",
    "kimi-k2.5",
    "unknown-model-xyz",
];

#[divan::bench(args = MODEL_IDS)]
fn context_window_lookup(model_id: &str) -> u32 {
    ...
}

#[divan::bench(args = MODEL_IDS)]
fn vision_support_lookup(model_id: &str) -> bool {
    ...
}

#[divan::bench]
fn namespaced_model_id() -> String {
    ...
}

// ── Session store ───────────────────────────────────────────────────────────

const SESSION_KEYS: &[&str] = &[
    "default",
    "project:backend:debug-auth",
    "2026-02-09T12:00:00Z",
    "user@host:session:42",
];

#[divan::bench(args = SESSION_KEYS)]
fn session_key_to_filename(key: &str) -> String {
    ...
}

fn build_sanitize_input(payload_bytes: usize) -> String {
    ...
}

#[divan::bench(args = [10_000, 100_000, 1_000_000])]
fn sanitize_tool_result(bencher: divan::Bencher, payload_bytes: usize) {
    ...
}

#[divan::bench(args = [10_000, 100_000, 1_000_000])]
fn tool_result_to_content_vision(bencher: divan::Bencher, payload_bytes: usize) {
    ...
}

fn build_persisted_messages(n: usize) -> Vec<serde_json::Value> {
    ...
}

#[divan::bench(args = [50, 500, 2000])]
fn values_to_chat_messages(bencher: divan::Bencher, n: usize) {
    ...
}

// ── Env substitution ────────────────────────────────────────────────────────

#[divan::bench]
fn env_substitution(bencher: divan::Bencher) {
    ...
}

// ── Config load from disk (simulated boot) ──────────────────────────────────

/// Full boot-path simulation: generate template, write to disk, load, validate.
#[divan::bench]
fn full_config_boot_path(bencher: divan::Bencher) {
    ...
}
