use moltis_channels::gating::{self, DmPolicy, GroupPolicy};

use crate::config::WhatsAppAccountConfig;

/// Determine if an inbound WhatsApp message should be processed.
///
/// Returns `Ok(())` if the message is allowed, or `Err(reason)` if it should
/// be denied. WhatsApp does not have @mention semantics like Telegram bots,
/// so there is no `MentionMode` gating.
pub fn check_access(
    config: &WhatsAppAccountConfig,
    is_group: bool,
    peer_id: &str,
    username: Option<&str>,
    group_id: Option<&str>,
) -> Result<(), AccessDenied> {
    ...
}

fn check_dm_access(
    config: &WhatsAppAccountConfig,
    peer_id: &str,
    username: Option<&str>,
) -> Result<(), AccessDenied> {
    ...
}

fn check_group_access(
    config: &WhatsAppAccountConfig,
    group_id: Option<&str>,
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
#[allow(clippy::unwrap_used)]
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
    fn group_open_allows_all() {
    ...
}

    #[test]
    fn group_disabled_rejects() {
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
    /// NOT silently switch to open access.
    #[test]
    fn security_removing_last_allowlist_entry_denies_access() {
    ...
}
}
