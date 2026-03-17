//! Argon2id key derivation for password → KEK.

use {argon2::Argon2, zeroize::Zeroizing};

use crate::error::VaultError;

/// Argon2id parameters stored alongside the wrapped DEK.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct KdfParams {
    ...
}

impl Default for KdfParams {
    fn default() -> Self {
}

/// Derive a 256-bit key from a password and salt using Argon2id.
pub fn derive_key(
    password: &[u8],
    salt: &[u8],
    params: &KdfParams,
) -> Result<Zeroizing<[u8; 32]>, VaultError> {
    ...
}

/// Generate a random 16-byte salt and return it as base64.
pub fn generate_salt() -> String {
    ...
}

/// Decode a base64-encoded salt.
pub fn decode_salt(b64: &str) -> Result<Vec<u8>, VaultError> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn different_passwords_different_keys() {
    ...
}

    #[test]
    fn different_salts_different_keys() {
    ...
}

    #[test]
    fn generate_and_decode_salt() {
    ...
}

    #[test]
    fn kdf_params_serialization() {
    ...
}
}
