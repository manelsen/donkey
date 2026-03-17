#[cfg(feature = "vault")]
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use {
    argon2::{
        Argon2,
        password_hash::{
            PasswordHash, PasswordHasher, PasswordVerifier, SaltString, rand_core::OsRng,
        },
    },
    secrecy::ExposeSecret,
    serde::{Deserialize, Serialize},
    sha2::{Digest, Sha256},
    sqlx::SqlitePool,
};

#[cfg(feature = "vault")]
use moltis_vault::Vault;

// ── Types ────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AuthMethod {
    ...
}

/// A verified identity after successful authentication.
#[derive(Debug, Clone)]
pub struct AuthIdentity {
    ...
}

/// A registered passkey entry (for listing in the UI).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PasskeyEntry {
    ...
}

/// An API key entry (for listing in the UI — never exposes the full key).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiKeyEntry {
    ...
}

/// Result of verifying an API key, including granted scopes.
#[derive(Debug, Clone)]
pub struct ApiKeyVerification {
    ...
}

/// All valid API key scopes.
pub const VALID_SCOPES: &[&str] = &[
    "operator.admin",
    "operator.read",
    "operator.write",
    "operator.approvals",
    "operator.pairing",
];

/// An environment variable entry (for listing in the UI — never exposes the value).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvVarEntry {
    ...
}

// ── Credential store ─────────────────────────────────────────────────────────

/// Single-user credential store backed by SQLite.
pub struct CredentialStore {
    ...
}

impl CredentialStore {
    /// Open a database at the given path, reset all auth, and close it.
    pub async fn reset_from_db_path(db_path: &std::path::Path) -> anyhow::Result<()> {

    /// Create a new store and initialize tables.
    /// Reads `auth.disabled` from the discovered config file.
    pub async fn new(pool: SqlitePool) -> anyhow::Result<Self> {
    ...
}

    /// Create a new store with explicit auth config (avoids reading from disk).
    pub async fn with_config(
        pool: SqlitePool,
        auth_config: &moltis_config::AuthConfig,
    ) -> anyhow::Result<Self> {
    ...
}

    /// Create a new store with vault support for encrypting environment variables.
    #[cfg(feature = "vault")]
    pub async fn with_vault(
        pool: SqlitePool,
        auth_config: &moltis_config::AuthConfig,
        vault: Option<Arc<Vault>>,
    ) -> anyhow::Result<Self> {
    ...
}

    /// Initialize auth tables.
    ///
    /// **Note**: Schema is now managed by sqlx migrations. This method is a no-op
    /// when running with the gateway (migrations have already run). It's retained
    /// for standalone tests that use in-memory databases.
    async fn init(&self) -> anyhow::Result<()> {
    ...
}

    // ── Setup ────────────────────────────────────────────────────────────

    /// Whether initial setup (password creation) has been completed.
    pub fn is_setup_complete(&self) -> bool {
    ...
}

    /// Whether authentication has been explicitly disabled via reset.
    pub fn is_auth_disabled(&self) -> bool {
    ...
}

    /// Clear the auth-disabled flag (e.g. after completing localhost setup without a password).
    pub async fn clear_auth_disabled(&self) -> anyhow::Result<()> {
    ...
}

    async fn persist_auth_disabled(&self, disabled: bool) -> anyhow::Result<()> {
    ...
}

    /// Whether a password has been set.
    pub async fn has_password(&self) -> anyhow::Result<bool> {
    ...
}

    // ── Password ─────────────────────────────────────────────────────────

    /// Set the initial password (first-run setup). Fails if already set.
    pub async fn set_initial_password(&self, password: &str) -> anyhow::Result<()> {
    ...
}

    /// Add a password when none exists yet (e.g. after passkey-only setup).
    ///
    /// This marks setup complete so auth is enforced immediately.
    pub async fn add_password(&self, password: &str) -> anyhow::Result<()> {
    ...
}

    /// Mark initial setup as complete without setting a password (e.g. passkey-only setup).
    ///
    /// Requires at least one credential (password or passkey) to already exist.
    pub async fn mark_setup_complete(&self) -> anyhow::Result<()> {
    ...
}

    /// Recompute `setup_complete` from the current credentials in the database.
    ///
    /// Called after removing a credential to ensure the auth state reflects
    /// reality. If no password and no passkeys remain, `setup_complete` is
    /// cleared so the middleware falls back to the "no auth" path.
    async fn recompute_setup_complete(&self) -> anyhow::Result<()> {
    ...
}

    /// Verify a password against the stored hash.
    pub async fn verify_password(&self, password: &str) -> anyhow::Result<bool> {
    ...
}

    /// Change the password (requires correct current password).
    ///
    /// Invalidates all existing sessions for defense-in-depth — even if the
    /// WebSocket disconnect misses a client, old sessions cannot be reused.
    pub async fn change_password(&self, current: &str, new_password: &str) -> anyhow::Result<()> {
    ...
}

    // ── Sessions ─────────────────────────────────────────────────────────

    /// Create a new session token (30-day expiry).
    pub async fn create_session(&self) -> anyhow::Result<String> {
    ...
}

    /// Validate a session token. Returns true if valid and not expired.
    pub async fn validate_session(&self, token: &str) -> anyhow::Result<bool> {
    ...
}

    /// Delete a session (logout).
    pub async fn delete_session(&self, token: &str) -> anyhow::Result<()> {
    ...
}

    /// Clean up expired sessions.
    pub async fn cleanup_expired_sessions(&self) -> anyhow::Result<u64> {
    ...
}

    // ── API Keys ─────────────────────────────────────────────────────────

    /// Generate a new API key with optional scopes. Returns (id, raw_key).
    /// The raw key is only shown once — we store only its SHA-256 hash.
    ///
    /// If `scopes` is None or empty, the key will have no access until scopes are set.
    pub async fn create_api_key(
        &self,
        label: &str,
        scopes: Option<&[String]>,
    ) -> anyhow::Result<(i64, String)> {
    ...
}

    /// List all API keys (active only, not revoked).
    pub async fn list_api_keys(&self) -> anyhow::Result<Vec<ApiKeyEntry>> {
    ...
}

    /// Revoke an API key by id.
    pub async fn revoke_api_key(&self, key_id: i64) -> anyhow::Result<()> {
    ...
}

    /// Verify a raw API key. Returns `Some(ApiKeyVerification)` if valid,
    /// `None` if invalid or revoked.
    pub async fn verify_api_key(
        &self,
        raw_key: &str,
    ) -> anyhow::Result<Option<ApiKeyVerification>> {
    ...
}

    // ── Environment Variables ─────────────────────────────────────────────

    /// List all environment variables (names only, no values).
    pub async fn list_env_vars(&self) -> anyhow::Result<Vec<EnvVarEntry>> {
    ...
}

    /// Set (upsert) an environment variable.
    ///
    /// When the vault feature is enabled and the vault is unsealed, the value
    /// is encrypted before storage and `encrypted` is set to `1`.
    pub async fn set_env_var(&self, key: &str, value: &str) -> anyhow::Result<i64> {
    ...
}

    /// Delete an environment variable by id. Returns the key name if found.
    pub async fn delete_env_var(&self, id: i64) -> anyhow::Result<Option<String>> {
    ...
}

    /// Get all environment variable key-value pairs (internal use for sandbox injection).
    ///
    /// When the vault feature is enabled, rows with `encrypted=1` are decrypted
    /// using the vault. Rows that fail decryption are skipped with a warning.
    pub async fn get_all_env_values(&self) -> anyhow::Result<Vec<(String, String)>> {
    ...
}

    // ── Reset (remove all auth) ─────────────────────────────────────────

    /// Remove all authentication data: password, sessions, passkeys, API keys.
    /// After this, `is_setup_complete()` returns false and the middleware
    /// passes all requests through (no auth required).
    pub async fn reset_all(&self) -> anyhow::Result<()> {
    ...
}

    // ── Vault accessors ────────────────────────────────────────────────

    /// Get a reference to the vault (if configured).
    #[cfg(feature = "vault")]
    pub fn vault(&self) -> Option<&Arc<Vault>> {
    ...
}

    /// Get a reference to the underlying database pool.
    pub fn db_pool(&self) -> &SqlitePool {
    ...
}

    // ── Passkeys ─────────────────────────────────────────────────────────

    /// Store a new passkey credential.
    pub async fn store_passkey(
        &self,
        credential_id: &[u8],
        name: &str,
        passkey_data: &[u8],
    ) -> anyhow::Result<i64> {
    ...
}

    /// List all registered passkeys.
    pub async fn list_passkeys(&self) -> anyhow::Result<Vec<PasskeyEntry>> {
    ...
}

    /// Remove a passkey by id.
    ///
    /// If this was the last credential (no password, no other passkeys),
    /// `setup_complete` is reset so the auth middleware stops requiring auth.
    pub async fn remove_passkey(&self, passkey_id: i64) -> anyhow::Result<()> {
    ...
}

    /// Rename a passkey.
    pub async fn rename_passkey(&self, passkey_id: i64, name: &str) -> anyhow::Result<()> {
    ...
}

    /// Load all passkey data blobs (for WebAuthn authentication).
    pub async fn load_all_passkey_data(&self) -> anyhow::Result<Vec<(i64, Vec<u8>)>> {
    ...
}

    /// Check if any passkeys are registered (for login page UI).
    pub async fn has_passkeys(&self) -> anyhow::Result<bool> {
    ...
}
}

// ── EnvVarProvider impl ─────────────────────────────────────────────────────

#[async_trait::async_trait]
impl moltis_tools::exec::EnvVarProvider for CredentialStore {
    async fn get_env_vars(&self) -> Vec<(String, secrecy::Secret<String>)> {
    ...
}
}

// ── Helpers ──────────────────────────────────────────────────────────────────

pub fn is_loopback(ip: &str) -> bool {
    ...
}

fn hash_password(password: &str) -> anyhow::Result<String> {
    ...
}

fn verify_password(password: &str, hash_str: &str) -> bool {
    ...
}

fn generate_token() -> String {
    ...
}

fn sha256_hex(input: &str) -> String {
    ...
}

// ── Legacy compat ────────────────────────────────────────────────────────────

/// Result of an authentication attempt.
#[derive(Debug, Clone)]
pub struct AuthResult {
    ...
}

/// Constant-time string comparison (prevents timing attacks).
fn safe_equal(a: &str, b: &str) -> bool {
    ...
}

/// Authenticate an incoming WebSocket connect request against legacy env-var auth.
pub fn authorize_connect(
    auth: &ResolvedAuth,
    provided_token: Option<&str>,
    provided_password: Option<&str>,
    _remote_ip: Option<&str>,
) -> AuthResult {
    ...
}

/// Legacy resolved auth from environment vars (kept for migration).
#[derive(Clone)]
pub struct ResolvedAuth {
    ...
}

impl std::fmt::Debug for ResolvedAuth {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AuthMode {
    ...
}

/// Resolve auth config from environment / config values.
pub fn resolve_auth(token: Option<String>, password: Option<String>) -> ResolvedAuth {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_password_hash_verify() {
    ...
}

    #[test]
    fn test_generate_token() {
    ...
}

    #[test]
    fn test_sha256_hex() {
    ...
}

    #[tokio::test]
    async fn test_credential_store_password() {
    ...
}

    #[tokio::test]
    async fn test_credential_store_sessions() {
    ...
}

    #[tokio::test]
    async fn test_credential_store_api_keys() {
    ...
}

    #[tokio::test]
    async fn test_credential_store_api_keys_with_scopes() {
    ...
}

    #[tokio::test]
    async fn test_credential_store_reset_all() {
    ...
}

    #[tokio::test]
    async fn test_auth_disabled_persists_across_restart() {
    ...
}

    #[tokio::test]
    async fn test_credential_store_env_vars() {
    ...
}

    #[tokio::test]
    async fn test_credential_store_passkeys() {
    ...
}

    #[tokio::test]
    async fn test_change_password_invalidates_sessions() {
    ...
}

    #[tokio::test]
    async fn test_add_password_marks_setup_complete_and_reenables_auth() {
    ...
}

    #[tokio::test]
    async fn test_store_passkey_marks_setup_complete_and_reenables_auth() {
    ...
}

    #[tokio::test]
    async fn test_mark_setup_complete_with_passkey_only() {
    ...
}

    #[tokio::test]
    async fn test_setup_complete_persists_with_passkey_only() {
    ...
}

    #[tokio::test]
    async fn test_removing_last_passkey_clears_setup_complete() {
    ...
}

    #[tokio::test]
    async fn test_removing_passkey_keeps_setup_when_password_exists() {
    ...
}

    // ── Vault integration tests ─────────────────────────────────────────

    /// Helper to create a vault-enabled credential store for tests.
    #[cfg(feature = "vault")]
    async fn vault_store(password: &str) -> (CredentialStore, Arc<Vault>) {
    ...
}

    #[cfg(feature = "vault")]
    #[tokio::test]
    async fn test_env_var_encryption_when_vault_unsealed() {
    ...
}

    #[cfg(feature = "vault")]
    #[tokio::test]
    async fn test_env_var_plaintext_when_vault_sealed() {
    ...
}

    #[cfg(feature = "vault")]
    #[tokio::test]
    async fn test_env_var_decrypt_round_trip() {
    ...
}
}
