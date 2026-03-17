use {async_trait::async_trait, sqlx::SqlitePool};

use moltis_channels::{
    Error as ChannelError, Result as ChannelResult,
    store::{ChannelStore, StoredChannel},
};

fn channel_db_error(context: &'static str, source: sqlx::Error) -> ChannelError {
    ...
}

/// Internal row type for sqlx mapping.
#[derive(sqlx::FromRow)]
struct ChannelRow {
    ...
}

impl TryFrom<ChannelRow> for StoredChannel {
    type Error = ChannelError;

    fn try_from(r: ChannelRow) -> ChannelResult<Self> {
}

/// SQLite-backed channel store.
pub struct SqliteChannelStore {
    ...
}

impl SqliteChannelStore {
    pub fn new(pool: SqlitePool) -> Self {

    /// Initialize the channels table schema.
    ///
    /// **Deprecated**: Schema is now managed by sqlx migrations.
    /// This method is retained for tests that use in-memory databases.
    #[doc(hidden)]
    pub async fn init(pool: &SqlitePool) -> ChannelResult<()> {
    ...
}
}

#[async_trait]
impl ChannelStore for SqliteChannelStore {
    async fn list(&self) -> ChannelResult<Vec<StoredChannel>> {

    async fn get(
        &self,
        channel_type: &str,
        account_id: &str,
    ) -> ChannelResult<Option<StoredChannel>> {
    ...
}

    async fn upsert(&self, channel: StoredChannel) -> ChannelResult<()> {
    ...
}

    async fn delete(&self, channel_type: &str, account_id: &str) -> ChannelResult<()> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn now() -> i64 {
    ...
}

    #[tokio::test]
    async fn test_upsert_and_get() {
    ...
}

    #[tokio::test]
    async fn test_upsert_updates_existing() {
    ...
}

    #[tokio::test]
    async fn test_delete() {
    ...
}

    #[tokio::test]
    async fn test_list_order() {
    ...
}

    #[tokio::test]
    async fn test_get_nonexistent() {
    ...
}
}
