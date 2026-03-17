use {
    base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD},
    rand::RngCore,
    sha2::{Digest, Sha256},
};

use crate::types::PkceChallenge;

/// Generate a PKCE S256 challenge pair.
pub fn generate_pkce() -> PkceChallenge {
    ...
}

/// Generate a random state parameter.
pub fn generate_state() -> String {
    ...
}
