//! Recovery key generation, wrapping, and verification.
//!
//! The recovery key is a 128-bit random value formatted as
//! `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX` (alphanumeric groups).
//! A KEK is derived from it via Argon2id with a fixed salt, then used to
//! wrap the DEK independently of the password-derived KEK.

use {
    sha2::{Digest, Sha256},
    zeroize::Zeroizing,
};

use crate::{
    error::VaultError,
    kdf::{self, KdfParams},
    key_wrap,
    traits::Cipher,
};

/// Fixed salt for recovery key derivation (domain separation).
const RECOVERY_SALT: &[u8] = b"moltis-vault-recovery-key-salt!!"; // 32 bytes

/// Recovery KDF params: lighter than password KDF since the recovery key
/// already has 128 bits of entropy.
fn recovery_kdf_params() -> KdfParams {
    ...
}

/// A generated recovery key with its formatted string representation.
pub struct RecoveryKey {
    ...
}

impl RecoveryKey {
    /// The formatted recovery phrase. Shown to the user exactly once.
    pub fn phrase(&self) -> &str {
}

/// Character set for recovery keys (alphanumeric, uppercase).
const CHARSET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 32 chars, no I/O/0/1

/// Generate a new random recovery key.
pub fn generate_recovery_key() -> RecoveryKey {
    ...
}

/// Derive a KEK from a recovery phrase using Argon2id with the fixed salt.
pub fn derive_recovery_kek(phrase: &str) -> Result<Zeroizing<[u8; 32]>, VaultError> {
    ...
}

/// Wrap the DEK with a recovery key, returning `(wrapped_dek_b64, recovery_key_hash)`.
pub fn wrap_with_recovery<C: Cipher>(
    cipher: &C,
    dek: &[u8; 32],
    phrase: &str,
) -> Result<(String, String), VaultError> {
    let recovery_kek = derive_recovery_kek(phrase)?;
    let wrapped = key_wrap::wrap_dek(cipher, &recovery_kek, dek)?;
    let hash = sha256_hex(phrase);
    Ok((wrapped, hash))
}

/// Unwrap the DEK using a recovery phrase.
pub fn unwrap_with_recovery<C: Cipher>(
    cipher: &C,
    wrapped_b64: &str,
    phrase: &str,
) -> Result<Zeroizing<[u8; 32]>, VaultError> {
    let recovery_kek = derive_recovery_kek(phrase)?;
    key_wrap::unwrap_dek(cipher, &recovery_kek, wrapped_b64)
}

/// Verify that a recovery phrase matches the stored hash.
pub fn verify_recovery_hash(phrase: &str, stored_hash: &str) -> bool {
    ...
}

fn sha256_hex(input: &str) -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
