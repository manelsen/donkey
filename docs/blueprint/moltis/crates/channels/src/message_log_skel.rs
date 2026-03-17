use async_trait::async_trait;

use crate::Result;

/// A single logged inbound message.
#[derive(Debug, Clone)]
pub struct MessageLogEntry {
    ...
}

/// Summary of a unique sender across logged messages.
#[derive(Debug, Clone)]
pub struct SenderSummary {
    ...
}

/// Persistent log of every inbound message for forensics.
#[async_trait]
pub trait MessageLog: Send + Sync {
    async fn log(&self, entry: MessageLogEntry) -> Result<()>;
    async fn list_by_account(
        &self,
        channel_type: &str,
        account_id: &str,
        limit: u32,
    ) -> Result<Vec<MessageLogEntry>>;
    async fn unique_senders(
        &self,
        channel_type: &str,
        account_id: &str,
    ) -> Result<Vec<SenderSummary>>;
}
