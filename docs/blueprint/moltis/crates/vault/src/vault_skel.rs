//! Vault state machine: initialization, seal/unseal, encrypt/decrypt.

use {base64::Engine, sqlx::SqlitePool, tokio::sync::RwLock, zeroize::Zeroizing};

use crate::{
    error::VaultError,
    kdf::{self, KdfParams},
    key_wrap,
    recovery::{self, RecoveryKey},
    traits::Cipher,
    xchacha20::XChaCha20Poly1305Cipher,
};

/// Vault status exposed to the API / frontend.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VaultStatus {
    ...
}

/// Row from the `vault_metadata` table.
#[derive(Debug)]
struct VaultRow {
    ...
}

/// Encryption-at-rest vault.
///
/// Generic over [`Cipher`] but defaults to [`XChaCha20Poly1305Cipher`].
/// The DEK is held in memory behind a `RwLock` — `None` means sealed.
pub struct Vault<C: Cipher = XChaCha20Poly1305Cipher> {
    ...
}

impl Vault<XChaCha20Poly1305Cipher> {
    /// Create a vault with the default XChaCha20-Poly1305 cipher.
    pub async fn new(pool: SqlitePool) -> Result<Self, VaultError> {
}

impl<C: Cipher> Vault<C> {
    /// Create a vault with a custom cipher.
    pub async fn with_cipher(pool: SqlitePool, cipher: C) -> Result<Self, VaultError> {
    ...
}

    /// Query the current vault status.
    pub async fn status(&self) -> Result<VaultStatus, VaultError> {
    ...
}

    /// Initialize the vault with a password.
    ///
    /// Generates a random DEK, wraps it with the password-derived KEK,
    /// generates a recovery key, and stores everything in the database.
    /// Returns the recovery key (shown to the user exactly once).
    pub async fn initialize(&self, password: &str) -> Result<RecoveryKey, VaultError> {
    ...
}

    /// Unseal the vault using a password.
    pub async fn unseal(&self, password: &str) -> Result<(), VaultError> {
    ...
}

    /// Unseal the vault using a recovery phrase.
    pub async fn unseal_with_recovery(&self, phrase: &str) -> Result<(), VaultError> {
    ...
}

    /// Seal the vault (clear the DEK from memory).
    pub async fn seal(&self) {
    ...
}

    /// Change the password. Re-wraps the DEK with the new password's KEK.
    ///
    /// The vault must already be unsealed (DEK in memory).
    pub async fn change_password(&self, old: &str, new: &str) -> Result<(), VaultError> {
    ...
}

    /// Encrypt a string and return a versioned base64 blob.
    ///
    /// The AAD (additional authenticated data) should identify the context,
    /// e.g. `"env:MY_KEY"` or `"provider_keys"`.
    pub async fn encrypt_string(&self, plaintext: &str, aad: &str) -> Result<String, VaultError> {
    ...
}

    /// Decrypt a base64 blob back to a string.
    pub async fn decrypt_string(&self, b64: &str, aad: &str) -> Result<String, VaultError> {
    ...
}

    /// Whether the vault is currently unsealed (DEK in memory).
    pub async fn is_unsealed(&self) -> bool {
    ...
}

    /// Load vault metadata from the database.
    async fn load_metadata(&self) -> Result<Option<VaultRow>, VaultError> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
