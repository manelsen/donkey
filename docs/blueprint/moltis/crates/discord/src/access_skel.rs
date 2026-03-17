use {
    moltis_channels::gating::{self, DmPolicy, GroupPolicy, MentionMode},
    moltis_common::types::ChatType,
};

use crate::config::DiscordAccountConfig;

/// Determine if an inbound message should be processed.
///
/// Returns `Ok(())` if the message is allowed, or `Err(reason)` if it should
/// be silently dropped.
pub fn check_access(
    config: &DiscordAccountConfig,
    chat_type: &ChatType,
    peer_id: &str,
    username: Option<&str>,
    guild_id: Option<&str>,
    bot_mentioned: bool,
) -> Result<(), AccessDenied> {
    ...
}

fn check_dm_access(
    config: &DiscordAccountConfig,
    peer_id: &str,
    username: Option<&str>,
) -> Result<(), AccessDenied> {
    ...
}

fn check_guild_access(
    config: &DiscordAccountConfig,
    guild_id: Option<&str>,
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
    fn allowlist_dm_matches_peer_id_or_username() {
    ...
}

    #[test]
    fn guild_mention_required() {
    ...
}

    #[test]
    fn guild_always_mode() {
    ...
}

    #[test]
    fn guild_disabled() {
    ...
}

    #[test]
    fn guild_allowlist() {
    ...
}

    #[test]
    fn empty_dm_allowlist_denies_all() {
    ...
}

    #[test]
    fn empty_guild_allowlist_denies_all() {
    ...
}

    #[test]
    fn security_removing_last_allowlist_entry_denies_access() {
    ...
}
}
