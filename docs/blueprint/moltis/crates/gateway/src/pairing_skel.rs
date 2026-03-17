//! Device pairing state machine and device token management.
//!
//! Pairing state is persisted to SQLite so it survives gateway restarts.
//! An in-memory cache provides fast reads; all mutations write through to DB.

use std::time::Duration;

use {
    serde::{Deserialize, Serialize},
    sha2::{Digest, Sha256},
    sqlx::SqlitePool,
    time::OffsetDateTime,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

pub type Result<T> = std::result::Result<T, Error>;

// ── Types ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PairStatus {
    ...
}

impl PairStatus {
    /// String representation used for DB storage and serialization.
    #[allow(dead_code)]
    fn as_str(self) -> &'static str {

    fn from_str(s: &str) -> Self {
    ...
}
}

#[derive(Debug, Clone)]
pub struct PairRequest {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceToken {
    ...
}

/// Result of verifying a device token.
#[derive(Debug, Clone)]
pub struct DeviceTokenVerification {
    ...
}

// ── Pairing store ───────────────────────────────────────────────────────────

/// SQLite-backed pairing store. Persists pair requests, paired devices, and
/// device tokens across gateway restarts.
pub struct PairingStore {
    ...
}

impl PairingStore {
    pub fn new(pool: SqlitePool) -> Self {

    /// Submit a new pairing request. Returns the generated request with nonce.
    pub async fn request_pair(
        &self,
        device_id: &str,
        display_name: Option<&str>,
        platform: &str,
        public_key: Option<&str>,
    ) -> Result<PairRequest> {
    ...
}

    /// List all non-expired pending requests.
    pub async fn list_pending(&self) -> Result<Vec<PairRequest>> {
    ...
}

    /// Approve a pending pair request. Issues a device token.
    pub async fn approve(&self, pair_id: &str) -> Result<DeviceToken> {
    ...
}

    /// Reject a pending pair request.
    pub async fn reject(&self, pair_id: &str) -> Result<()> {
    ...
}

    /// List all approved (non-revoked) devices.
    pub async fn list_devices(&self) -> Result<Vec<PairedDevice>> {
    ...
}

    /// List device tokens for a specific device (active only).
    pub async fn list_device_tokens(&self, device_id: &str) -> Result<Vec<DeviceTokenEntry>> {
    ...
}

    /// Rotate a device token: revoke all existing tokens, issue new.
    pub async fn rotate_token(&self, device_id: &str) -> Result<DeviceToken> {
    ...
}

    /// Revoke all tokens for a device and mark device as revoked.
    pub async fn revoke_token(&self, device_id: &str) -> Result<()> {
    ...
}

    /// Verify a raw device token. Returns device identity and scopes if valid.
    pub async fn verify_device_token(
        &self,
        raw_token: &str,
    ) -> Result<Option<DeviceTokenVerification>> {
    ...
}

    /// Create a pre-authorized device and issue a token directly (no pairing handshake).
    pub async fn create_device_token(
        &self,
        display_name: Option<&str>,
        platform: &str,
    ) -> Result<DeviceToken> {
    ...
}

    /// Evict expired pending requests.
    pub async fn evict_expired(&self) -> Result<u64> {
    ...
}
}

// ── Additional types ────────────────────────────────────────────────────────

/// A paired device (for listing).
#[derive(Debug, Clone, Serialize)]
pub struct PairedDevice {
    ...
}

/// A device token entry (for listing — never exposes raw token).
#[derive(Debug, Clone, Serialize)]
pub struct DeviceTokenEntry {
    ...
}

// ── In-memory pairing state (kept for backward compat during transition) ────

/// In-memory pairing state for use when no database is available (tests).
pub struct PairingState {
    ...
}

impl Default for PairingState {
    fn default() -> Self {
}

impl PairingState {
    pub fn new() -> Self {

    pub fn request_pair(
        &mut self,
        device_id: &str,
        display_name: Option<&str>,
        platform: &str,
        public_key: Option<&str>,
    ) -> PairRequest {
    ...
}

    pub fn list_pending(&self) -> Vec<&PairRequest> {
    ...
}

    pub fn approve(&mut self, pair_id: &str) -> Result<DeviceToken> {
    ...
}

    pub fn reject(&mut self, pair_id: &str) -> Result<()> {
    ...
}

    pub fn list_devices(&self) -> Vec<&DeviceToken> {
    ...
}

    pub fn rotate_token(&mut self, device_id: &str) -> Result<DeviceToken> {
    ...
}

    pub fn revoke_token(&mut self, device_id: &str) -> Result<()> {
    ...
}

    /// Create a pre-authorized device and issue a token directly (no pairing handshake).
    pub fn create_device_token(
        &mut self,
        display_name: Option<&str>,
        platform: &str,
    ) -> DeviceToken {
    ...
}

    pub fn evict_expired(&mut self) {
    ...
}
}

// ── Helpers ─────────────────────────────────────────────────────────────────

fn generate_token() -> String {
    ...
}

fn sha256_hex(input: &str) -> String {
    ...
}

fn current_epoch_ms() -> u64 {
    ...
}

fn format_datetime(dt: OffsetDateTime) -> String {
    ...
}

fn is_expired(expires_at: &str) -> bool {
    ...
}

fn is_expired_sqlite(expires_at: &str) -> bool {
    ...
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn pairing_lifecycle() {
    ...
}

    #[tokio::test]
    async fn reject_pair_request() {
    ...
}

    #[tokio::test]
    async fn approve_nonexistent_request() {
    ...
}

    #[tokio::test]
    async fn verify_invalid_token() {
    ...
}

    #[tokio::test]
    async fn create_device_token_directly() {
    ...
}

    #[tokio::test]
    async fn rotate_nonexistent_device() {
    ...
}
}
