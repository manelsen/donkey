//! DEK wrapping / unwrapping using the [`Cipher`] trait.
//!
//! The DEK (Data Encryption Key) is encrypted with the KEK (Key Encryption Key)
//! using the same AEAD cipher as data encryption. The AAD is fixed to `"dek-wrap"`
//! to domain-separate key wrapping from data encryption.

use {base64::Engine, zeroize::Zeroizing};

use crate::{error::VaultError, traits::Cipher};

/// AAD used for key wrapping, distinct from data encryption AAD.
const WRAP_AAD: &[u8] = b"dek-wrap";

/// Wrap (encrypt) a DEK with a KEK using the given cipher.
///
/// Returns the wrapped blob as base64 (prefixed with the cipher's version tag).
pub fn wrap_dek<C: Cipher>(
    cipher: &C,
    kek: &[u8; 32],
    dek: &[u8; 32],
) -> Result<String, VaultError> {
    let encrypted = cipher.encrypt(kek, dek, WRAP_AAD)?;

    let mut blob = Vec::with_capacity(1 + encrypted.len());
    blob.push(cipher.version_tag());
    blob.extend_from_slice(&encrypted);

    Ok(base64::engine::general_purpose::STANDARD.encode(blob))
}

/// Unwrap (decrypt) a DEK from a base64-encoded wrapped blob.
///
/// Validates the version tag matches the expected cipher.
pub fn unwrap_dek<C: Cipher>(
    cipher: &C,
    kek: &[u8; 32],
    wrapped_b64: &str,
) -> Result<Zeroizing<[u8; 32]>, VaultError> {
    let blob = base64::engine::general_purpose::STANDARD.decode(wrapped_b64)?;

    if blob.is_empty() {
        return Err(VaultError::CipherError("empty wrapped DEK".to_string()));
    }

    let version = blob[0];
    if version != cipher.version_tag() {
        return Err(VaultError::CipherError(format!(
            "unsupported cipher version: {version:#04x}, expected {:#04x}",
            cipher.version_tag()
        )));
    }

    let plaintext = cipher.decrypt(kek, &blob[1..], WRAP_AAD)?;

    if plaintext.len() != 32 {
        return Err(VaultError::CipherError(format!(
            "unwrapped DEK has wrong length: {} (expected 32)",
            plaintext.len()
        )));
    }

    let mut dek = Zeroizing::new([0u8; 32]);
    dek.copy_from_slice(&plaintext);
    Ok(dek)
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
