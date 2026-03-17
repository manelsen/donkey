//! Local LLM provider setup service.
//!
//! Provides RPC handlers for configuring the local GGUF LLM provider,
//! including system info detection, model listing, and model configuration.

use std::{
    fmt,
    path::{Path, PathBuf},
    sync::Arc,
};

use {
    async_trait::async_trait,
    base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD},
    serde::{Deserialize, Serialize},
    serde_json::Value,
    tokio::sync::{OnceCell, RwLock, watch},
    tracing::{info, warn},
};

use moltis_providers::{ProviderRegistry, local_gguf, local_llm, raw_model_id};

use crate::{
    broadcast::{BroadcastOpts, broadcast},
    services::{LocalLlmService, ServiceResult},
    state::GatewayState,
};

#[derive(Debug, thiserror::Error)]
pub enum LocalModelCacheError {
    ...
}

impl LocalModelCacheError {
    #[must_use]
    pub fn message(message: impl fmt::Display) -> Self {
}

pub type LocalModelCacheResult<T> = Result<T, LocalModelCacheError>;

type DownloadProgressUpdate = (u64, Option<u64>);
const LOCAL_LLM_PROVIDER_NAME: &str = "local-llm";

fn download_progress_percent(downloaded: u64, total: Option<u64>) -> Option<f64> {
    ...
}

fn spawn_download_progress_broadcaster(
    state: &Arc<GatewayState>,
    model_id: &str,
    display_name: &str,
) -> (
    watch::Sender<Option<DownloadProgressUpdate>>,
    tokio::task::JoinHandle<()>,
) {
    ...
}

/// Check if a local model is cached on disk, and download it if not.
///
/// Returns Ok(true) if download was needed and completed successfully.
/// Returns Ok(false) if model was already cached.
/// Returns Err if download failed.
pub async fn ensure_local_model_cached(
    model_id: &str,
    state: &Arc<GatewayState>,
) -> LocalModelCacheResult<bool> {
    ...
}

/// Download a model from the unified registry with progress broadcasting.
async fn download_unified_model(
    model: &'static local_llm::models::LocalModelDef,
    backend: local_llm::backend::BackendType,
    cache_dir: &Path,
    state: &Arc<GatewayState>,
) -> LocalModelCacheResult<bool> {
    ...
}

/// Download a model from the legacy registry with progress broadcasting.
async fn download_legacy_model(
    model: &'static local_gguf::models::GgufModelDef,
    cache_dir: &Path,
    state: &Arc<GatewayState>,
) -> LocalModelCacheResult<bool> {
    ...
}

/// Download an arbitrary HuggingFace GGUF file with progress broadcasting.
async fn download_custom_gguf_model(
    model_id: &str,
    hf_repo: &str,
    hf_filename: &str,
    cache_dir: &Path,
    state: &Arc<GatewayState>,
) -> LocalModelCacheResult<bool> {
    ...
}

/// Download an arbitrary HuggingFace MLX repo with progress broadcasting.
async fn download_hf_mlx_repo(
    hf_repo: &str,
    cache_dir: &Path,
    state: &Arc<GatewayState>,
) -> LocalModelCacheResult<bool> {
    ...
}

/// Check if mlx-lm is installed (either via pip or brew).
fn is_mlx_installed() -> bool {
    ...
}

/// Detect available package managers for installing mlx-lm.
/// Returns a list of (name, install_command) pairs, ordered by preference.
fn detect_mlx_installers() -> Vec<(&'static str, &'static str)> {
    ...
}

/// Single model entry in the local-llm config.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalModelEntry {
    ...
}

fn default_backend() -> String {
    ...
}

/// Configuration file for local-llm stored in the config directory.
/// Supports multiple models.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LocalLlmConfig {
    ...
}

/// Legacy single-model config for migration.
#[derive(Debug, Clone, Deserialize)]
struct LegacyLocalLlmConfig {
    ...
}

impl LocalLlmConfig {
    /// Load config from the config directory.
    /// Handles migration from legacy single-model format.
    pub fn load() -> Option<Self> {

    /// Save config to the config directory.
    pub fn save(&self) -> anyhow::Result<()> {
    ...
}

    /// Add a model to the config. Replaces if model_id already exists.
    pub fn add_model(&mut self, entry: LocalModelEntry) {
    ...
}

    /// Remove a model by ID. Returns true if model was found and removed.
    pub fn remove_model(&mut self, model_id: &str) -> bool {
    ...
}

    /// Get a model by ID.
    pub fn get_model(&self, model_id: &str) -> Option<&LocalModelEntry> {
    ...
}
}

impl LocalModelEntry {
    fn backend_type(&self) -> Option<local_llm::backend::BackendType> {

    fn custom_gguf_source(&self) -> Option<(&str, &str)> {
    ...
}

    fn resolved_model_path(
        &self,
        default_model_path: Option<&Path>,
        cache_dir: &Path,
    ) -> anyhow::Result<Option<PathBuf>> {
    ...
}

    fn display_name(&self) -> String {
    ...
}
}

fn custom_gguf_model_id(hf_repo: &str, hf_filename: &str) -> String {
    ...
}

fn legacy_custom_gguf_model_id(hf_repo: &str) -> String {
    ...
}

fn remove_conflicting_custom_gguf_entries(
    config: &mut LocalLlmConfig,
    hf_repo: &str,
    hf_filename: &str,
) -> Vec<String> {
    ...
}

fn status_from_saved_config(config: Option<&LocalLlmConfig>) -> LocalLlmStatus {
    ...
}

fn build_local_provider_entry(
    entry: &LocalModelEntry,
    default_model_path: Option<&Path>,
) -> anyhow::Result<(
    moltis_providers::ModelInfo,
    Arc<local_llm::LocalLlmProvider>,
)> {
    ...
}

fn configured_local_model_path_override(
    providers_config: &moltis_config::schema::ProvidersConfig,
) -> Option<PathBuf> {
    ...
}

fn unregister_local_model_from_registry(registry: &mut ProviderRegistry, model_id: &str) {
    ...
}

fn unregister_local_model_ids_from_registry(registry: &mut ProviderRegistry, model_ids: &[String]) {
    ...
}

fn register_local_model_entry(
    registry: &mut ProviderRegistry,
    entry: &LocalModelEntry,
) -> anyhow::Result<()> {
    ...
}

fn register_local_model_entry_with_default_model_path(
    registry: &mut ProviderRegistry,
    entry: &LocalModelEntry,
    default_model_path: Option<&Path>,
) -> anyhow::Result<()> {
    ...
}

pub fn register_saved_local_models(
    registry: &mut ProviderRegistry,
    providers_config: &moltis_config::schema::ProvidersConfig,
) {
    ...
}

/// Status of the local LLM provider.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "status", rename_all = "lowercase")]
pub enum LocalLlmStatus {
    ...
}

/// Live implementation of LocalLlmService.
pub struct LiveLocalLlmService {
    ...
}

impl LiveLocalLlmService {
    pub fn new(registry: Arc<RwLock<ProviderRegistry>>) -> Self {

    /// Set the gateway state reference for broadcasting progress updates.
    pub fn set_state(&self, state: Arc<GatewayState>) {
    ...
}

    /// Get model display info for JSON response.
    fn model_to_json(model: &local_gguf::models::GgufModelDef, is_suggested: bool) -> Value {
    ...
}
}

fn has_enough_ram(total_ram_gb: u32, required_ram_gb: u32) -> bool {
    ...
}

fn insufficient_ram_error(
    model_display_name: &str,
    required_ram_gb: u32,
    total_ram_gb: u32,
) -> String {
    ...
}

#[async_trait]
impl LocalLlmService for LiveLocalLlmService {
    async fn system_info(&self) -> ServiceResult {

    async fn models(&self) -> ServiceResult {
    ...
}

    async fn configure(&self, params: Value) -> ServiceResult {
    ...
}

    async fn status(&self) -> ServiceResult {
    ...
}

    async fn search_hf(&self, params: Value) -> ServiceResult {
    ...
}

    async fn configure_custom(&self, params: Value) -> ServiceResult {
    ...
}

    async fn remove_model(&self, params: Value) -> ServiceResult {
    ...
}
}

/// Search HuggingFace for models matching the query and backend.
async fn search_huggingface(
    query: &str,
    backend: &str,
    limit: usize,
) -> Result<Vec<Value>, String> {
    ...
}

/// HuggingFace model info from API response.
#[derive(Debug, serde::Deserialize)]
struct HfModelInfo {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
