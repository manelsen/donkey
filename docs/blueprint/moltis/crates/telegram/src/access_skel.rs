use {
    moltis_channels::gating::{self, DmPolicy, GroupPolicy, MentionMode},
    moltis_common::types::ChatType,
};

use crate::config::TelegramAccountConfig;

/// Determine if an inbound message should be processed.
///
/// Returns `Ok(())` if the message is allowed, or `Err(reason)` if it should
/// be silently dropped.
pub fn check_access(
    config: &TelegramAccountConfig,
    chat_type: &ChatType,
    peer_id: &str,
    username: Option<&str>,
    group_id: Option<&str>,
    bot_mentioned: bool,
) -> Result<(), AccessDenied> {
    ...
}

fn check_dm_access(
    config: &TelegramAccountConfig,
    peer_id: &str,
    username: Option<&str>,
) -> Result<(), AccessDenied> {
    ...
}

fn check_group_access(
    config: &TelegramAccountConfig,
    _peer_id: &str,
    group_id: Option<&str>,
    bot_mentioned: bool,
) -> Result<(), AccessDenied> {
    ...
}

/// Reason an inbound message was denied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AccessDenied {
    ...
}

impl std::fmt::Display for AccessDenied {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

#[cfg(test)]
mod tests {

    #[test]
    fn open_dm_allows_all() {
    ...
}

    #[test]
    fn disabled_dm_rejects() {
    ...
}

    #[test]
    fn allowlist_dm_by_peer_id() {
    ...
}

    #[test]
    fn allowlist_dm_by_username() {
    ...
}

    #[test]
    fn group_mention_required() {
    ...
}

    #[test]
    fn group_always_mode() {
    ...
}

    #[test]
    fn group_disabled() {
    ...
}

    #[test]
    fn group_allowlist() {
    ...
}

    #[test]
    fn empty_dm_allowlist_denies_all() {
    ...
}

    #[test]
    fn empty_group_allowlist_denies_all() {
    ...
}

    /// Security regression: removing the last entry from an allowlist must
    /// NOT silently switch to open access.  An explicit Allowlist policy with
    /// an empty list must deny every peer — by peer ID, by username, and in
    /// groups alike.  Failure here means unauthenticated users can bypass the
    /// allowlist by convincing an admin to remove all entries.
    #[test]
    fn security_removing_last_allowlist_entry_denies_access() {
    ...
}
}
