//! Persists dynamic client registrations for MCP OAuth servers.
//!
//! Stores client credentials at `~/.config/moltis/mcp_oauth_registrations.json`
//! so that re-registration is avoided on subsequent connections.

use std::{collections::HashMap, fmt::Write as _, path::PathBuf};

use {
    secrecy::Secret,
    serde::{Deserialize, Serialize},
    sha2::{Digest, Sha256},
    tracing::{debug, info, warn},
};

use crate::{Result, config_dir::moltis_config_dir};

/// A stored dynamic client registration.
#[derive(Clone, Serialize, Deserialize)]
pub struct StoredRegistration {
    ...
}

impl std::fmt::Debug for StoredRegistration {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// File-based store for MCP OAuth client registrations.
#[derive(Debug, Clone)]
pub struct RegistrationStore {
    ...
}

impl RegistrationStore {
    pub fn new() -> Self {

    /// Create a store at a specific path (useful for testing).
    pub fn with_path(path: PathBuf) -> Self {
    ...
}

    /// Load a stored registration for the given server URL.
    pub fn load(&self, server_url: &str) -> Option<StoredRegistration> {
    ...
}

    /// Save a registration for the given server URL.
    pub fn save(&self, server_url: &str, reg: &StoredRegistration) -> Result<()> {
    ...
}

    /// Delete a stored registration.
    pub fn delete(&self, server_url: &str) -> Result<()> {
    ...
}
}

fn server_lookup_key(server_url: &str) -> String {
    ...
}

impl Default for RegistrationStore {
    fn default() -> Self {
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn sample_registration() -> StoredRegistration {
    ...
}

    #[test]
    fn roundtrip_save_load() {
    ...
}

    #[test]
    fn load_nonexistent_returns_none() {
    ...
}

    #[test]
    fn load_supports_legacy_raw_url_keys() {
    ...
}

    #[test]
    fn delete_registration() {
    ...
}

    #[test]
    fn delete_nonexistent_is_ok() {
    ...
}

    #[test]
    fn multiple_servers() {
    ...
}

    #[cfg(unix)]
    #[test]
    fn file_permissions_are_0600() {
    ...
}

    #[test]
    fn no_client_secret_roundtrip() {
    ...
}

    #[test]
    fn debug_redacts_secret() {
    ...
}
}
