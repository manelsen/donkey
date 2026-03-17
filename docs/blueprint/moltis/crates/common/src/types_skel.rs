use serde::{Deserialize, Serialize};

/// Unique identifier for an agent.
pub type AgentId = String;

/// Unique identifier for a channel account.
pub type AccountId = String;

/// Unique identifier for a peer (user on a channel).
pub type PeerId = String;

/// Channel identifier (e.g. "telegram", "discord", "whatsapp").
pub type ChannelId = String;

/// Chat type for routing and session scoping.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ChatType {
    ...
}

/// Normalized inbound message context (mirrors MsgContext from TypeScript).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MsgContext {
    ...
}

/// Outbound reply payload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReplyPayload {
    ...
}

/// Media attachment for outbound messages.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaAttachment {
    ...
}
