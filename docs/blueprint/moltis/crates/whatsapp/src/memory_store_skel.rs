//! In-memory storage backend for whatsapp-rust.
//!
//! This is a temporary solution while `whatsapp-rust-sqlite-storage` has a
//! `libsqlite3-sys` version conflict with `sqlx`. Session state does NOT
//! persist across restarts — the user must re-scan the QR code.
//!
//! TODO: Replace with `whatsapp-rust-sqlite-storage` once sqlx 0.9 stabilises
//! (it uses a range-based libsqlite3-sys dep that resolves the conflict).

use std::{fmt::Write, sync::Arc};

use {
    async_trait::async_trait,
    dashmap::DashMap,
    wacore::{
        appstate::{hash::HashState, processor::AppStateMutationMAC},
        store::{error::Result, traits::*},
    },
};

/// Hex-encode bytes without pulling in the `hex` crate.
fn hex_encode(bytes: &[u8]) -> String {
    ...
}

/// In-memory store implementing all wacore storage traits.
#[derive(Clone, Default)]
pub struct MemoryStore {
    ...
}

impl MemoryStore {
    pub fn new() -> Self {
}

// ============================================================================
// SignalStore
// ============================================================================

#[async_trait]
impl SignalStore for MemoryStore {
    async fn put_identity(&self, address: &str, key: [u8; 32]) -> Result<()> {

    async fn load_identity(&self, address: &str) -> Result<Option<Vec<u8>>> {
    ...
}

    async fn delete_identity(&self, address: &str) -> Result<()> {
    ...
}

    async fn get_session(&self, address: &str) -> Result<Option<Vec<u8>>> {
    ...
}

    async fn put_session(&self, address: &str, session: &[u8]) -> Result<()> {
    ...
}

    async fn delete_session(&self, address: &str) -> Result<()> {
    ...
}

    async fn store_prekey(&self, id: u32, record: &[u8], uploaded: bool) -> Result<()> {
    ...
}

    async fn load_prekey(&self, id: u32) -> Result<Option<Vec<u8>>> {
    ...
}

    async fn remove_prekey(&self, id: u32) -> Result<()> {
    ...
}

    async fn store_signed_prekey(&self, id: u32, record: &[u8]) -> Result<()> {
    ...
}

    async fn load_signed_prekey(&self, id: u32) -> Result<Option<Vec<u8>>> {
    ...
}

    async fn load_all_signed_prekeys(&self) -> Result<Vec<(u32, Vec<u8>)>> {
    ...
}

    async fn remove_signed_prekey(&self, id: u32) -> Result<()> {
    ...
}

    async fn put_sender_key(&self, address: &str, record: &[u8]) -> Result<()> {
    ...
}

    async fn get_sender_key(&self, address: &str) -> Result<Option<Vec<u8>>> {
    ...
}

    async fn delete_sender_key(&self, address: &str) -> Result<()> {
    ...
}
}

// ============================================================================
// AppSyncStore
// ============================================================================

#[async_trait]
impl AppSyncStore for MemoryStore {
    async fn get_sync_key(&self, key_id: &[u8]) -> Result<Option<AppStateSyncKey>> {

    async fn set_sync_key(&self, key_id: &[u8], key: AppStateSyncKey) -> Result<()> {
    ...
}

    async fn get_version(&self, name: &str) -> Result<HashState> {
    ...
}

    async fn set_version(&self, name: &str, state: HashState) -> Result<()> {
    ...
}

    async fn put_mutation_macs(
        &self,
        name: &str,
        version: u64,
        mutations: &[AppStateMutationMAC],
    ) -> Result<()> {
    ...
}

    async fn get_mutation_mac(&self, name: &str, index_mac: &[u8]) -> Result<Option<Vec<u8>>> {
    ...
}

    async fn delete_mutation_macs(&self, name: &str, index_macs: &[Vec<u8>]) -> Result<()> {
    ...
}
}

// ============================================================================
// ProtocolStore
// ============================================================================

#[async_trait]
impl ProtocolStore for MemoryStore {
    async fn get_skdm_recipients(&self, group_jid: &str) -> Result<Vec<String>> {

    async fn add_skdm_recipients(&self, group_jid: &str, device_jids: &[String]) -> Result<()> {
    ...
}

    async fn clear_skdm_recipients(&self, group_jid: &str) -> Result<()> {
    ...
}

    async fn get_lid_mapping(&self, lid: &str) -> Result<Option<LidPnMappingEntry>> {
    ...
}

    async fn get_pn_mapping(&self, phone: &str) -> Result<Option<LidPnMappingEntry>> {
    ...
}

    async fn put_lid_mapping(&self, entry: &LidPnMappingEntry) -> Result<()> {
    ...
}

    async fn get_all_lid_mappings(&self) -> Result<Vec<LidPnMappingEntry>> {
    ...
}

    async fn save_base_key(&self, address: &str, message_id: &str, base_key: &[u8]) -> Result<()> {
    ...
}

    async fn has_same_base_key(
        &self,
        address: &str,
        message_id: &str,
        current_base_key: &[u8],
    ) -> Result<bool> {
    ...
}

    async fn delete_base_key(&self, address: &str, message_id: &str) -> Result<()> {
    ...
}

    async fn update_device_list(&self, record: DeviceListRecord) -> Result<()> {
    ...
}

    async fn get_devices(&self, user: &str) -> Result<Option<DeviceListRecord>> {
    ...
}

    async fn mark_forget_sender_key(&self, group_jid: &str, participant: &str) -> Result<()> {
    ...
}

    async fn consume_forget_marks(&self, group_jid: &str) -> Result<Vec<String>> {
    ...
}
}

// ============================================================================
// DeviceStore
// ============================================================================

#[async_trait]
impl DeviceStore for MemoryStore {
    async fn save(&self, device: &wacore::store::Device) -> Result<()> {

    async fn load(&self) -> Result<Option<wacore::store::Device>> {
    ...
}

    async fn exists(&self) -> Result<bool> {
    ...
}

    async fn create(&self) -> Result<i32> {
    ...
}
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[tokio::test]
    async fn session_roundtrip() {
    ...
}

    #[tokio::test]
    async fn device_store_roundtrip() {
    ...
}

    #[tokio::test]
    async fn prekey_operations() {
    ...
}

    #[tokio::test]
    async fn signed_prekey_operations() {
    ...
}

    #[tokio::test]
    async fn sender_key_roundtrip() {
    ...
}

    #[tokio::test]
    async fn sync_key_roundtrip() {
    ...
}

    #[tokio::test]
    async fn version_roundtrip() {
    ...
}

    #[tokio::test]
    async fn skdm_recipients() {
    ...
}

    #[tokio::test]
    async fn lid_mapping() {
    ...
}

    #[tokio::test]
    async fn base_key_operations() {
    ...
}

    #[tokio::test]
    async fn device_list() {
    ...
}

    #[tokio::test]
    async fn forget_marks() {
    ...
}
}
