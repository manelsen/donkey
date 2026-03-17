//! In-memory OTP state for self-approval of non-allowlisted DM users.
//!
//! When `dm_policy = Allowlist` and `otp_self_approval = true`, the bot issues
//! a 6-digit OTP challenge to unknown users. If they reply with the correct
//! code they are automatically added to the allowlist.

use std::{
    collections::HashMap,
    time::{Duration, Instant, SystemTime},
};

use rand::Rng;

/// How long an OTP code stays valid.
const OTP_TTL: Duration = Duration::from_secs(300);

/// Maximum wrong-code attempts before lockout.
const MAX_ATTEMPTS: u32 = 3;

/// Per-account OTP state.
pub struct OtpState {
    ...
}

/// A pending OTP challenge for a single peer.
pub struct OtpChallenge {
    ...
}

/// Lockout state after too many failed attempts.
struct Lockout {
    ...
}

/// Result of initiating a challenge.
#[derive(Debug, PartialEq, Eq)]
pub enum OtpInitResult {
    ...
}

/// Result of verifying a code.
#[derive(Debug, PartialEq, Eq)]
pub enum OtpVerifyResult {
    ...
}

/// Snapshot of a pending challenge for external consumers (API/UI).
#[derive(Debug, Clone, serde::Serialize)]
pub struct OtpChallengeInfo {
    ...
}

impl OtpState {
    pub fn new(cooldown_secs: u64) -> Self {

    /// Update the lockout cooldown duration (takes effect on future lockouts).
    pub fn set_cooldown(&mut self, cooldown_secs: u64) {
    ...
}

    /// Initiate an OTP challenge for `peer_id`.
    pub fn initiate(
        &mut self,
        peer_id: &str,
        username: Option<String>,
        sender_name: Option<String>,
    ) -> OtpInitResult {
    ...
}

    /// Verify a code submitted by `peer_id`.
    pub fn verify(&mut self, peer_id: &str, code: &str) -> OtpVerifyResult {
    ...
}

    /// Check if a challenge is pending (and not expired) for `peer_id`.
    pub fn has_pending(&self, peer_id: &str) -> bool {
    ...
}

    /// Check if `peer_id` is currently locked out.
    pub fn is_locked_out(&self, peer_id: &str) -> bool {
    ...
}

    /// List all pending (non-expired) challenges with epoch timestamps.
    pub fn list_pending(&self) -> Vec<OtpChallengeInfo> {
    ...
}

    /// Remove expired challenges and elapsed lockouts.
    pub fn evict_expired(&mut self) {
    ...
}
}

/// Generate a random 6-digit OTP code.
fn generate_otp_code() -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn initiate_already_pending() {
    ...
}

    #[test]
    fn verify_correct_code() {
    ...
}

    #[test]
    fn verify_wrong_code() {
    ...
}

    #[test]
    fn verify_no_pending() {
    ...
}

    #[test]
    fn verify_expired() {
    ...
}

    #[test]
    fn lockout_prevents_initiate() {
    ...
}

    #[test]
    fn lockout_prevents_verify() {
    ...
}

    #[test]
    fn evict_expired_clears_old_entries() {
    ...
}

    #[test]
    fn evict_expired_clears_elapsed_lockouts() {
    ...
}

    #[test]
    fn list_pending_returns_active_challenges() {
    ...
}

    #[test]
    fn expired_challenge_allows_new_initiate() {
    ...
}

    #[test]
    fn otp_code_is_six_digits() {
    ...
}
}
