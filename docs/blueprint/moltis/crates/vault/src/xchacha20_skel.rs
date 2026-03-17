//! XChaCha20-Poly1305 implementation of the [`Cipher`] trait.

#[allow(deprecated)] // upstream generic-array 0.x deprecation
use chacha20poly1305::{
    XChaCha20Poly1305, XNonce,
    aead::{Aead, KeyInit, Payload},
};
use rand::RngCore;

use crate::{error::VaultError, traits::Cipher};

/// Version tag for the XChaCha20-Poly1305 cipher.
pub const VERSION_TAG: u8 = 0x01;

/// Nonce size for XChaCha20-Poly1305 (24 bytes).
const NONCE_LEN: usize = 24;

/// XChaCha20-Poly1305 AEAD cipher.
///
/// Encrypted blob layout: `[nonce: 24 bytes][ciphertext + Poly1305 tag: N + 16 bytes]`.
pub struct XChaCha20Poly1305Cipher;

impl Cipher for XChaCha20Poly1305Cipher {
    fn version_tag(&self) -> u8 {

    #[allow(deprecated)]
    fn encrypt(&self, key: &[u8; 32], plaintext: &[u8], aad: &[u8]) -> Result<Vec<u8>, VaultError> {
    ...
}

    #[allow(deprecated)]
    fn decrypt(
        &self,
        key: &[u8; 32],
        ciphertext: &[u8],
        aad: &[u8],
    ) -> Result<Vec<u8>, VaultError> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn round_trip_with_aad() {
    ...
}

    #[test]
    fn wrong_key_fails() {
    ...
}

    #[test]
    fn wrong_aad_fails() {
    ...
}

    #[test]
    fn tampered_ciphertext_fails() {
    ...
}

    #[test]
    fn too_short_ciphertext_fails() {
    ...
}

    #[test]
    fn different_nonces_produce_different_ciphertexts() {
    ...
}

    #[test]
    fn version_tag_is_0x01() {
    ...
}

    #[test]
    fn empty_plaintext_round_trip() {
    ...
}

    #[test]
    fn large_plaintext_round_trip() {
    ...
}
}
