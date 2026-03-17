use std::{
    net::TcpListener,
    path::{Path, PathBuf},
    sync::Mutex,
};

use tracing::{debug, info, warn};

use crate::{
    env_subst::substitute_env,
    schema::{AgentIdentity, MoltisConfig, ResolvedIdentity, UserProfile},
};

/// Generate a random available port by binding to port 0 and reading the assigned port.
fn generate_random_port() -> u16 {
    ...
}

/// Standard config file names, checked in order.
const CONFIG_FILENAMES: &[&str] = &["moltis.toml", "moltis.yaml", "moltis.yml", "moltis.json"];

/// Override for the config directory, set via `set_config_dir()`.
static CONFIG_DIR_OVERRIDE: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Override for the data directory, set via `set_data_dir()`.
static DATA_DIR_OVERRIDE: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Override for the share directory, set via `set_share_dir()`.
static SHARE_DIR_OVERRIDE: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Set a custom config directory. When set, config discovery only looks in
/// this directory (project-local and user-global paths are skipped).
/// Can be called multiple times (e.g. in tests) — each call replaces the
/// previous override.
pub fn set_config_dir(path: PathBuf) {
    ...
}

/// Clear the config directory override, restoring default discovery.
pub fn clear_config_dir() {
    ...
}

fn config_dir_override() -> Option<PathBuf> {
    ...
}

/// Set a custom data directory. When set, `data_dir()` returns this path
/// instead of the default.
pub fn set_data_dir(path: PathBuf) {
    ...
}

/// Clear the data directory override, restoring default discovery.
pub fn clear_data_dir() {
    ...
}

fn data_dir_override() -> Option<PathBuf> {
    ...
}

/// Set a custom share directory (for tests or alternative layouts).
pub fn set_share_dir(path: PathBuf) {
    ...
}

/// Clear the share directory override, restoring default discovery.
pub fn clear_share_dir() {
    ...
}

fn share_dir_override() -> Option<PathBuf> {
    ...
}

/// Returns the share directory for external assets (web files, WASM components).
///
/// Resolution order:
/// 1. Programmatic override via `set_share_dir()`
/// 2. `MOLTIS_SHARE_DIR` env var
/// 3. `/usr/share/moltis/` (Linux system packages) — only if it exists
/// 4. `data_dir()/share/` (`~/.moltis/share/`) — only if it exists
/// 5. `None` (fall back to embedded assets)
pub fn share_dir() -> Option<PathBuf> {
    ...
}

/// Load config from the given path (any supported format).
///
/// After parsing, `MOLTIS_*` env vars are applied as overrides.
pub fn load_config(path: &Path) -> crate::Result<MoltisConfig> {
    ...
}

/// Load and parse the config file with env substitution and includes.
pub fn load_config_value(path: &Path) -> crate::Result<serde_json::Value> {
    ...
}

/// Discover and load config from standard locations.
///
/// Search order:
/// 1. `./moltis.{toml,yaml,yml,json}` (project-local)
/// 2. `~/.config/moltis/moltis.{toml,yaml,yml,json}` (user-global)
///
/// Returns `MoltisConfig::default()` if no config file is found.
///
/// If the config has port 0 (either from defaults or missing `[server]` section),
/// a random available port is generated and saved to the config file.
pub fn discover_and_load() -> MoltisConfig {
    ...
}

/// Find the first config file in standard locations.
///
/// When a config dir override is set, only that directory is searched —
/// project-local and user-global paths are skipped for isolation.
pub fn find_config_file() -> Option<PathBuf> {
    ...
}

/// Returns the config directory: programmatic override → `MOLTIS_CONFIG_DIR` env →
/// `~/.config/moltis/`.
pub fn config_dir() -> Option<PathBuf> {
    ...
}

/// Returns the user-global config directory (`~/.config/moltis`) without
/// considering overrides like `MOLTIS_CONFIG_DIR`.
pub fn user_global_config_dir() -> Option<PathBuf> {
    ...
}

/// Returns the user-global config directory only when it differs from the
/// active config directory (i.e. when `MOLTIS_CONFIG_DIR` or `--config-dir`
/// is overriding the default). Returns `None` when they are the same path.
pub fn user_global_config_dir_if_different() -> Option<PathBuf> {
    ...
}

/// Finds a config file in the user-global config directory only.
pub fn find_user_global_config_file() -> Option<PathBuf> {
    ...
}

/// Returns the data directory: programmatic override → `MOLTIS_DATA_DIR` env →
/// `~/.moltis/`.
pub fn data_dir() -> PathBuf {
    ...
}

/// Path to the workspace soul file.
pub fn soul_path() -> PathBuf {
    ...
}

/// Path to the workspace AGENTS markdown.
pub fn agents_path() -> PathBuf {
    ...
}

/// Path to the workspace identity file.
pub fn identity_path() -> PathBuf {
    ...
}

/// Path to the workspace user profile file.
pub fn user_path() -> PathBuf {
    ...
}

/// Path to workspace tool-guidance markdown.
pub fn tools_path() -> PathBuf {
    ...
}

/// Path to workspace heartbeat markdown.
pub fn heartbeat_path() -> PathBuf {
    ...
}

/// Path to the workspace `MEMORY.md` file.
pub fn memory_path() -> PathBuf {
    ...
}

/// Return the workspace directory for a named agent: `data_dir()/agents/<id>`.
pub fn agent_workspace_dir(agent_id: &str) -> PathBuf {
    ...
}

/// Load identity values from `IDENTITY.md` frontmatter if present.
pub fn load_identity() -> Option<AgentIdentity> {
    ...
}

/// Load identity values for a specific agent workspace.
///
/// For `"main"`, this checks `data_dir()/agents/main/IDENTITY.md` first and
/// falls back to the root `IDENTITY.md`.
pub fn load_identity_for_agent(agent_id: &str) -> Option<AgentIdentity> {
    ...
}

/// Build a fully-resolved identity by merging all sources:
/// `moltis.toml` `[identity]` + `IDENTITY.md` frontmatter + `USER.md` + `SOUL.md`.
///
/// This is the single source of truth used by both the gateway (`identity_get`)
/// and the Swift FFI bridge.
pub fn resolve_identity() -> ResolvedIdentity {
    ...
}

/// Like [`resolve_identity`] but accepts a pre-loaded config.
pub fn resolve_identity_from_config(config: &MoltisConfig) -> ResolvedIdentity {
    ...
}

/// Load user values from `USER.md` frontmatter if present.
pub fn load_user() -> Option<UserProfile> {
    ...
}

/// Default soul text used when the user hasn't written their own.
///
/// Sourced from OpenClaw:
/// <https://github.com/openclaw/openclaw/blob/main/docs/reference/templates/SOUL.md>
pub const DEFAULT_SOUL: &str = "\
# SOUL.md - Who You Are\n\
\n\
_You're not a chatbot. You're becoming someone._\n\
\n\
## Core Truths\n\
\n\
**Be genuinely helpful, not performatively helpful.** Skip the \"Great question!\" \
and \"I'd be happy to help!\" — just help. Actions speak louder than filler words.\n\
\n\
**Have opinions.** You're allowed to disagree, prefer things, find stuff amusing \
or boring. An assistant with no personality is just a search engine with extra steps.\n\
\n\
**Be resourceful before asking.** Try to figure it out. Read the file. Check the \
context. Search for it. _Then_ ask if you're stuck. The goal is to come back with \
answers, not questions.\n\
\n\
**Earn trust through competence.** Your human gave you access to their stuff. Don't \
make them regret it. Be careful with external actions (emails, tweets, anything \
public). Be bold with internal ones (reading, organizing, learning).\n\
\n\
**Remember you're a guest.** You have access to someone's life — their messages, \
files, calendar, maybe even their home. That's intimacy. Treat it with respect.\n\
\n\
## Boundaries\n\
\n\
- Private things stay private. Period.\n\
- When in doubt, ask before acting externally.\n\
- Never send half-baked replies to messaging surfaces.\n\
- You're not the user's voice — be careful in group chats.\n\
\n\
## Vibe\n\
\n\
Be the assistant you'd actually want to talk to. Concise when needed, thorough \
when it matters. Not a corporate drone. Not a sycophant. Just... good.\n\
\n\
## Continuity\n\
\n\
Each session, you wake up fresh. These files _are_ your memory. Read them. Update \
them. They're how you persist.\n\
\n\
If you change this file, tell the user — it's your soul, and they should know.\n\
\n\
---\n\
\n\
_This file is yours to evolve. As you learn who you are, update it._";

/// Load SOUL.md from the workspace root (`data_dir`) if present and non-empty.
///
/// When the file does not exist, it is seeded with [`DEFAULT_SOUL`] (mirroring
/// how `discover_and_load()` writes `moltis.toml` on first run).
pub fn load_soul() -> Option<String> {
    ...
}

/// Load SOUL.md for a specific agent workspace.
///
/// For `"main"`, this checks `data_dir()/agents/main/SOUL.md` first and
/// falls back to the root `SOUL.md`.
pub fn load_soul_for_agent(agent_id: &str) -> Option<String> {
    ...
}

/// Write `DEFAULT_SOUL` to `SOUL.md` when the file doesn't already exist.
fn write_default_soul() -> crate::Result<()> {
    ...
}

/// Load AGENTS.md from the workspace root (`data_dir`) if present and non-empty.
pub fn load_agents_md() -> Option<String> {
    ...
}

/// Load AGENTS.md for a specific agent, falling back to the root file.
pub fn load_agents_md_for_agent(agent_id: &str) -> Option<String> {
    ...
}

/// Load TOOLS.md from the workspace root (`data_dir`) if present and non-empty.
pub fn load_tools_md() -> Option<String> {
    ...
}

/// Load TOOLS.md for a specific agent, falling back to the root file.
pub fn load_tools_md_for_agent(agent_id: &str) -> Option<String> {
    ...
}

/// Load HEARTBEAT.md from the workspace root (`data_dir`) if present and non-empty.
pub fn load_heartbeat_md() -> Option<String> {
    ...
}

/// Load MEMORY.md from the workspace root (`data_dir`) if present and non-empty.
pub fn load_memory_md() -> Option<String> {
    ...
}

/// Load MEMORY.md for a specific agent workspace.
///
/// For `"main"`, this checks `data_dir()/agents/main/MEMORY.md` first and
/// falls back to the root `MEMORY.md`.
pub fn load_memory_md_for_agent(agent_id: &str) -> Option<String> {
    ...
}

/// Persist SOUL.md in the workspace root (`data_dir`).
///
/// - `Some(non-empty)` writes `SOUL.md` with the given content
/// - `None` or empty writes an empty `SOUL.md` so that `load_soul()`
///   returns `None` without re-seeding the default
pub fn save_soul(soul: Option<&str>) -> crate::Result<PathBuf> {
    ...
}

/// Persist SOUL.md into an agent's workspace directory.
///
/// For the main agent this writes to `agents/main/SOUL.md` so that
/// `load_soul_for_agent("main")` picks it up on the primary read path.
pub fn save_soul_for_agent(agent_id: &str, soul: Option<&str>) -> crate::Result<PathBuf> {
    ...
}

/// Persist identity values to `IDENTITY.md` using YAML frontmatter.
pub fn save_identity(identity: &AgentIdentity) -> crate::Result<PathBuf> {
    ...
}

/// Persist identity values for an agent into its workspace directory.
pub fn save_identity_for_agent(agent_id: &str, identity: &AgentIdentity) -> crate::Result<PathBuf> {
    ...
}

/// Persist user values to `USER.md` using YAML frontmatter.
pub fn save_user(user: &UserProfile) -> crate::Result<PathBuf> {
    ...
}

pub fn extract_yaml_frontmatter(content: &str) -> Option<&str> {
    ...
}

fn parse_identity_frontmatter(frontmatter: &str) -> AgentIdentity {
    ...
}

fn parse_user_frontmatter(frontmatter: &str) -> UserProfile {
    ...
}

fn unquote_yaml_scalar(value: &str) -> &str {
    ...
}

fn yaml_scalar(value: &str) -> String {
    ...
}

fn load_workspace_markdown(path: PathBuf) -> Option<String> {
    ...
}

fn load_identity_from_path(path: &Path) -> Option<AgentIdentity> {
    ...
}

fn strip_leading_html_comments(content: &str) -> &str {
    ...
}

/// Returns the user's home directory (`$HOME` / `~`).
///
/// This is the **single call-site** for `directories::BaseDirs` — all other
/// crates must call this via `moltis_config::home_dir()` instead of using the
/// `directories` crate directly.
pub fn home_dir() -> Option<PathBuf> {
    ...
}

/// Returns the path of an existing config file, or the default TOML path.
pub fn find_or_default_config_path() -> PathBuf {
    ...
}

/// Lock guarding config read-modify-write cycles.
struct ConfigSaveState {
    ...
}

/// Lock guarding config read-modify-write cycles and the target config path
/// being synchronized.
static CONFIG_SAVE_LOCK: Mutex<ConfigSaveState> = Mutex::new(ConfigSaveState { target_path: None });

/// Atomically load the current config, apply `f`, and save.
///
/// Acquires a process-wide lock so concurrent callers cannot race.
/// Returns the path written to.
pub fn update_config(f: impl FnOnce(&mut MoltisConfig)) -> crate::Result<PathBuf> {
    ...
}

/// Serialize `config` to TOML and write it to the user-global config path.
///
/// Creates parent directories if needed. Returns the path written to.
///
/// Prefer [`update_config`] for read-modify-write cycles to avoid races.
pub fn save_config(config: &MoltisConfig) -> crate::Result<PathBuf> {
    ...
}

/// Write raw TOML to the config file, preserving comments.
///
/// Validates the input by parsing it first. Acquires the config save lock
/// so concurrent callers cannot race.  Returns the path written to.
pub fn save_raw_config(toml_str: &str) -> crate::Result<PathBuf> {
    ...
}

/// Serialize `config` to TOML and write it to the provided path.
///
/// For existing TOML files, this preserves user comments by merging the new
/// serialized values into the current document structure before writing.
pub fn save_config_to_path(path: &Path, config: &MoltisConfig) -> crate::Result<PathBuf> {
    ...
}

fn merge_toml_preserving_comments(path: &Path, updated_toml: &str) -> crate::Result<()> {
    ...
}

fn merge_toml_tables(current: &mut toml_edit::Table, updated: &toml_edit::Table) {
    ...
}

fn merge_toml_items(current: &mut toml_edit::Item, updated: &toml_edit::Item) {
    ...
}

/// Write the default config file to the user-global config path.
/// Only called when no config file exists yet.
/// Uses a comprehensive template with all options documented.
fn write_default_config(path: &Path, config: &MoltisConfig) -> crate::Result<()> {
    ...
}

/// Apply `MOLTIS_*` environment variable overrides to a loaded config.
///
/// Maps env vars to config fields using `__` as a section separator and
/// lowercasing. For example:
/// - `MOLTIS_AUTH_DISABLED=true` → `auth.disabled = true`
/// - `MOLTIS_TOOLS_EXEC_DEFAULT_TIMEOUT_SECS=60` → `tools.exec.default_timeout_secs = 60`
/// - `MOLTIS_CHAT_MESSAGE_QUEUE_MODE=collect` → `chat.message_queue_mode = "collect"`
///
/// The config is serialized to a JSON value, env overrides are merged in,
/// then deserialized back. Only env vars with the `MOLTIS_` prefix are
/// considered. `MOLTIS_CONFIG_DIR`, `MOLTIS_DATA_DIR`, `MOLTIS_SHARE_DIR`,
/// `MOLTIS_ASSETS_DIR`, `MOLTIS_TOKEN`, `MOLTIS_PASSWORD`, `MOLTIS_TAILSCALE`,
/// `MOLTIS_WEBAUTHN_RP_ID`, and `MOLTIS_WEBAUTHN_ORIGIN` are excluded
/// (they are handled separately).
pub fn apply_env_overrides(config: MoltisConfig) -> MoltisConfig {
    ...
}

/// Apply env overrides from an arbitrary iterator of (key, value) pairs.
/// Exposed for testing without mutating the process environment.
fn apply_env_overrides_with(
    config: MoltisConfig,
    vars: impl Iterator<Item = (String, String)>,
) -> MoltisConfig {
    ...
}

/// Parse a string env value into a JSON value, trying bool and number first.
fn parse_env_value(val: &str) -> serde_json::Value {
    ...
}

/// Set a value at a nested JSON path, creating intermediate objects as needed.
fn set_nested(root: &mut serde_json::Value, path: &[String], val: serde_json::Value) {
    ...
}

fn parse_config(raw: &str, path: &Path) -> crate::Result<MoltisConfig> {
    ...
}

fn parse_config_value(raw: &str, path: &Path) -> crate::Result<serde_json::Value> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    static DATA_DIR_TEST_LOCK: Mutex<TestDataDirState> =
        Mutex::new(TestDataDirState { _data_dir: None });

    #[test]
    fn parse_env_value_bool() {
    ...
}

    #[test]
    fn parse_env_value_number() {
    ...
}

    #[test]
    fn parse_env_value_string() {
    ...
}

    #[test]
    fn parse_env_value_json_array() {
    ...
}

    #[test]
    fn set_nested_creates_intermediate_objects() {
    ...
}

    #[test]
    fn set_nested_overwrites_existing() {
    ...
}

    #[test]
    fn apply_env_overrides_auth_disabled() {
    ...
}

    #[test]
    fn apply_env_overrides_tools_agent_timeout() {
    ...
}

    #[test]
    fn apply_env_overrides_tools_agent_max_iterations() {
    ...
}

    #[test]
    fn apply_env_overrides_ignores_excluded() {
    ...
}

    #[test]
    fn apply_env_overrides_multiple() {
    ...
}

    #[test]
    fn apply_env_overrides_deep_nesting() {
    ...
}

    #[test]
    fn apply_env_overrides_providers_offered_array() {
    ...
}

    #[test]
    fn apply_env_overrides_providers_offered_empty_array() {
    ...
}

    #[test]
    fn generate_random_port_returns_valid_port() {
    ...
}

    #[test]
    fn generate_random_port_returns_different_ports() {
    ...
}

    #[test]
    fn write_default_config_writes_template_to_requested_path() {
    ...
}

    #[test]
    fn write_default_config_does_not_overwrite_existing_file() {
    ...
}

    #[test]
    fn save_config_to_path_preserves_provider_and_voice_comment_blocks() {
    ...
}

    #[test]
    fn save_config_to_path_removes_stale_keys_when_values_are_cleared() {
    ...
}

    #[test]
    fn server_config_default_port_is_zero() {
    ...
}

    #[test]
    fn data_dir_override_works() {
    ...
}

    #[test]
    fn save_and_load_identity_frontmatter() {
    ...
}

    #[test]
    fn save_identity_removes_empty_file() {
    ...
}

    #[test]
    fn save_and_load_user_frontmatter() {
    ...
}

    #[test]
    fn save_and_load_user_with_location() {
    ...
}

    #[test]
    fn save_user_removes_empty_file() {
    ...
}

    #[test]
    fn load_tools_md_reads_trimmed_content() {
    ...
}

    #[test]
    fn load_agents_md_reads_trimmed_content() {
    ...
}

    #[test]
    fn load_heartbeat_md_reads_trimmed_content() {
    ...
}

    #[test]
    fn load_memory_md_reads_trimmed_content() {
    ...
}

    #[test]
    fn load_memory_md_returns_none_when_missing() {
    ...
}

    #[test]
    fn memory_path_is_under_data_dir() {
    ...
}

    #[test]
    fn workspace_markdown_ignores_leading_html_comments() {
    ...
}

    #[test]
    fn workspace_markdown_comment_only_is_treated_as_empty() {
    ...
}

    #[test]
    fn load_soul_creates_default_when_missing() {
    ...
}

    #[test]
    fn load_soul_does_not_overwrite_existing() {
    ...
}

    #[test]
    fn load_soul_reseeds_after_deletion() {
    ...
}

    #[test]
    fn save_soul_none_prevents_reseed() {
    ...
}

    #[test]
    fn save_soul_some_overwrites_default() {
    ...
}

    #[test]
    fn save_soul_for_agent_writes_to_agent_dir() {
    ...
}

    #[test]
    fn save_soul_for_agent_none_clears() {
    ...
}

    // ── share_dir tests ─────────────────────────────────────────────────

    #[test]
    fn share_dir_override_takes_precedence() {
    ...
}

    #[test]
    fn share_dir_returns_none_when_no_source() {
    ...
}

    #[test]
    fn share_dir_data_dir_fallback() {
    ...
}
}
