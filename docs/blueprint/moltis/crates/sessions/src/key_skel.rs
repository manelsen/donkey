/// Session key: agent:<id>:main or agent:<id>:channel:<ch>:account:<acct>:peer:<kind>:<id>
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SessionKey(pub String);

/// DM scope mode for session key generation.
#[derive(Debug, Clone)]
pub enum DmScope {
    ...
}

impl SessionKey {
    pub fn main(agent_id: &str) -> Self {

    pub fn for_peer(
        agent_id: &str,
        channel: &str,
        account: &str,
        peer_kind: &str,
        peer_id: &str,
    ) -> Self {
    ...
}
}
