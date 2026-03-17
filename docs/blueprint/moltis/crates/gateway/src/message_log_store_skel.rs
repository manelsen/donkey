use {
    async_trait::async_trait,
    moltis_channels::{
        Error as ChannelError, Result as ChannelResult,
        message_log::{MessageLog, MessageLogEntry, SenderSummary},
    },
    sqlx::SqlitePool,
};

fn channel_db_error(context: &'static str, source: sqlx::Error) -> ChannelError {
    ...
}

/// SQLite-backed message log.
pub struct SqliteMessageLog {
    ...
}

impl SqliteMessageLog {
    pub fn new(pool: SqlitePool) -> Self {

    /// Initialize the message_log table schema.
    ///
    /// **Deprecated**: Schema is now managed by sqlx migrations.
    /// This method is retained for tests that use in-memory databases.
    #[doc(hidden)]
    pub async fn init(pool: &SqlitePool) -> ChannelResult<()> {
    ...
}
}

#[async_trait]
impl MessageLog for SqliteMessageLog {
    async fn log(&self, entry: MessageLogEntry) -> ChannelResult<()> {

    async fn list_by_account(
        &self,
        channel_type: &str,
        account_id: &str,
        limit: u32,
    ) -> ChannelResult<Vec<MessageLogEntry>> {
    ...
}

    async fn unique_senders(
        &self,
        channel_type: &str,
        account_id: &str,
    ) -> ChannelResult<Vec<SenderSummary>> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn sample_entry(account_id: &str, peer_id: &str, granted: bool) -> MessageLogEntry {
    ...
}

    #[tokio::test]
    async fn log_and_list() {
    ...
}

    #[tokio::test]
    async fn list_respects_limit() {
    ...
}

    #[tokio::test]
    async fn unique_senders_groups() {
    ...
}
}
