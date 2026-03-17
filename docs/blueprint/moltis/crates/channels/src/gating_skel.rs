use serde::{Deserialize, Serialize};

/// Check if a peer is allowed to interact with the bot.
///
/// An empty allowlist means everyone is allowed (open policy).
/// Entries are matched case-insensitively against the peer ID.
/// Supports exact match and glob-style `*` wildcards.
pub fn is_allowed(peer_id: &str, allowlist: &[String]) -> bool {
    ...
}

/// Simple glob matching supporting `*` as a wildcard for any sequence of chars.
fn glob_match(pattern: &str, text: &str) -> bool {
    ...
}

/// Mention activation mode for group chats.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum MentionMode {
    ...
}

/// DM access policy.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DmPolicy {
    ...
}

/// Group access policy.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum GroupPolicy {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn exact_match() {
    ...
}

    #[test]
    fn glob_wildcard() {
    ...
}

    #[test]
    fn glob_suffix() {
    ...
}

    #[test]
    fn glob_middle() {
    ...
}
}
