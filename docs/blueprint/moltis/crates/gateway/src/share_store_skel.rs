use {
    anyhow::Result,
    base64::Engine,
    rand::RngCore,
    sha2::{Digest, Sha256},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ShareVisibility {
    ...
}

impl ShareVisibility {
    #[must_use]
    pub fn as_str(self) -> &'static str {
}

impl std::str::FromStr for ShareVisibility {
    type Err = &'static str;

    fn from_str(value: &str) -> std::result::Result<Self, Self::Err> {
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SharedMessageRole {
    ...
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct SharedMapLinks {
    ...
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedImageAsset {
    ...
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedImageSet {
    ...
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedMessage {
    ...
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShareSnapshot {
    ...
}

#[derive(Debug, Clone)]
pub struct SessionShare {
    ...
}

#[derive(Debug, Clone)]
pub struct CreatedShare {
    ...
}

#[derive(sqlx::FromRow)]
struct ShareRow {
    ...
}

impl TryFrom<ShareRow> for SessionShare {
    type Error = anyhow::Error;

    fn try_from(row: ShareRow) -> Result<Self, Self::Error> {
}

pub struct ShareStore {
    ...
}

impl ShareStore {
    #[must_use]
    pub fn new(pool: sqlx::SqlitePool) -> Self {

    /// Deprecated: schema is managed by sqlx migrations. Kept for tests.
    #[doc(hidden)]
    pub async fn init(pool: &sqlx::SqlitePool) -> Result<()> {
    ...
}

    pub async fn create_or_replace(
        &self,
        session_key: &str,
        visibility: ShareVisibility,
        snapshot_json: String,
        snapshot_message_count: u32,
    ) -> Result<CreatedShare> {
    ...
}

    pub async fn get_by_id(&self, id: &str) -> Result<Option<SessionShare>> {
    ...
}

    pub async fn get_active_by_id(&self, id: &str) -> Result<Option<SessionShare>> {
    ...
}

    pub async fn list_for_session(&self, session_key: &str) -> Result<Vec<SessionShare>> {
    ...
}

    pub async fn revoke(&self, id: &str) -> Result<bool> {
    ...
}

    pub async fn increment_views(&self, id: &str) -> Result<u64> {
    ...
}

    #[must_use]
    pub fn verify_access_key(share: &SessionShare, access_key: &str) -> bool {
    ...
}
}

fn now_ms() -> u64 {
    ...
}

fn generate_access_key() -> String {
    ...
}

fn hash_token(token: &str) -> String {
    ...
}

fn nibble_to_hex(v: u8) -> char {
    ...
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn create_public_share_replaces_previous_active_share() {
    ...
}

    #[tokio::test]
    async fn private_share_requires_valid_access_key() {
    ...
}

    #[tokio::test]
    async fn increment_views_counts_only_active_share() {
    ...
}
}
