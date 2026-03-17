//! Web-UI API handlers (bootstrap, skills, images, containers, media, logs).

use std::{collections::HashMap, path::PathBuf};

use {
    axum::{
        Json,
        extract::{Path, Query, State},
        http::StatusCode,
        response::{IntoResponse, Response},
    },
    moltis_gateway::server::AppState,
    moltis_tools::image_cache::ImageBuilder,
    tracing::warn,
};

use crate::templates::{build_nav_counts, onboarding_completed};

const MCP_LIST_FAILED: &str = "MCP_LIST_FAILED";
const IMAGE_CACHE_DELETE_FAILED: &str = "IMAGE_CACHE_DELETE_FAILED";
const IMAGE_CACHE_PRUNE_FAILED: &str = "IMAGE_CACHE_PRUNE_FAILED";
const SANDBOX_CHECK_PACKAGES_FAILED: &str = "SANDBOX_CHECK_PACKAGES_FAILED";
const SANDBOX_BACKEND_UNAVAILABLE: &str = "SANDBOX_BACKEND_UNAVAILABLE";
const SANDBOX_IMAGE_NAME_REQUIRED: &str = "SANDBOX_IMAGE_NAME_REQUIRED";
const SANDBOX_IMAGE_PACKAGES_REQUIRED: &str = "SANDBOX_IMAGE_PACKAGES_REQUIRED";
const SANDBOX_IMAGE_NAME_INVALID: &str = "SANDBOX_IMAGE_NAME_INVALID";
const SANDBOX_TMP_DIR_CREATE_FAILED: &str = "SANDBOX_TMP_DIR_CREATE_FAILED";
const SANDBOX_DOCKERFILE_WRITE_FAILED: &str = "SANDBOX_DOCKERFILE_WRITE_FAILED";
const SANDBOX_IMAGE_BUILD_FAILED: &str = "SANDBOX_IMAGE_BUILD_FAILED";
const SANDBOX_CONTAINERS_LIST_FAILED: &str = "SANDBOX_CONTAINERS_LIST_FAILED";
const SANDBOX_CONTAINER_PREFIX_MISMATCH: &str = "SANDBOX_CONTAINER_PREFIX_MISMATCH";
const SANDBOX_CONTAINER_STOP_FAILED: &str = "SANDBOX_CONTAINER_STOP_FAILED";
const SANDBOX_CONTAINER_REMOVE_FAILED: &str = "SANDBOX_CONTAINER_REMOVE_FAILED";
const SANDBOX_CONTAINERS_CLEAN_FAILED: &str = "SANDBOX_CONTAINERS_CLEAN_FAILED";
const SANDBOX_DISK_USAGE_FAILED: &str = "SANDBOX_DISK_USAGE_FAILED";
const SANDBOX_DAEMON_RESTART_FAILED: &str = "SANDBOX_DAEMON_RESTART_FAILED";
const SANDBOX_SHARED_HOME_SAVE_FAILED: &str = "SANDBOX_SHARED_HOME_SAVE_FAILED";
const SESSION_HISTORY_FAILED: &str = "SESSION_HISTORY_FAILED";
const SESSION_LIST_FAILED: &str = "SESSION_LIST_FAILED";
const SESSION_LIST_DEFAULT_LIMIT: usize = 40;
const SESSION_LIST_MAX_LIMIT: usize = 200;
const SESSION_HISTORY_DEFAULT_LIMIT: usize = 120;
const SESSION_HISTORY_MAX_LIMIT: usize = 500;

fn api_error(code: &str, error: impl Into<String>) -> serde_json::Value {
    ...
}

fn api_error_response(status: StatusCode, code: &str, error: impl Into<String>) -> Response {
    ...
}

#[derive(serde::Deserialize)]
pub struct SandboxSharedHomeUpdateRequest {
    ...
}

fn shared_home_config_payload(config: &moltis_config::MoltisConfig) -> serde_json::Value {
    ...
}

// ── Session media ────────────────────────────────────────────────────────────

#[derive(serde::Deserialize, Default)]
pub struct SessionListQuery {
    ...
}

fn clamp_session_list_limit(limit: Option<usize>) -> usize {
    ...
}

pub async fn api_sessions_handler(
    Query(query): Query<SessionListQuery>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ...
}

#[derive(serde::Deserialize)]
pub struct SessionHistoryQuery {
    ...
}

fn filter_ui_history(messages: Vec<serde_json::Value>) -> Vec<serde_json::Value> {
    ...
}

fn history_index(msg: &serde_json::Value) -> Option<usize> {
    ...
}

fn paginated_history(
    history: Vec<serde_json::Value>,
    cursor: Option<usize>,
    limit: usize,
) -> (Vec<serde_json::Value>, bool, Option<u64>) {
    ...
}

fn clamp_history_limit(limit: Option<usize>) -> usize {
    ...
}

#[derive(serde::Deserialize, Default)]
pub struct BootstrapQuery {
    ...
}

impl BootstrapQuery {
    fn channels_enabled(&self) -> bool {

    fn sessions_enabled(&self) -> bool {
    ...
}

    fn models_enabled(&self) -> bool {
    ...
}

    fn projects_enabled(&self) -> bool {
    ...
}

    fn counts_enabled(&self) -> bool {
    ...
}

    fn identity_enabled(&self) -> bool {
    ...
}
}

pub async fn api_session_history_handler(
    Path(session_key): Path<String>,
    Query(query): Query<SessionHistoryQuery>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ...
}

pub async fn api_session_media_handler(
    Path((session_key, filename)): Path<(String, String)>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ...
}

// ── Logs download ────────────────────────────────────────────────────────────

pub async fn api_logs_download_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

// ── Bootstrap ────────────────────────────────────────────────────────────────

pub async fn api_bootstrap_handler(
    Query(query): Query<BootstrapQuery>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ...
}

async fn api_bootstrap_with_query(
    gw: &moltis_gateway::state::GatewayState,
    query: &BootstrapQuery,
) -> Response {
    ...
}

// ── MCP / Hooks ──────────────────────────────────────────────────────────────

pub async fn api_mcp_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

pub async fn api_hooks_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

// ── Skills ───────────────────────────────────────────────────────────────────

fn enabled_from_manifest<E>(path_result: Result<PathBuf, E>) -> Vec<serde_json::Value>
where
    E: std::fmt::Display,
{
    let Ok(path) = path_result else {
        return Vec::new();
    };
    let store = moltis_skills::manifest::ManifestStore::new(path);
    store
        .load()
        .map(|m| {
            m.repos
                .iter()
                .flat_map(|repo| {
                    let source = repo.source.clone();
                    repo.skills.iter().filter(|s| s.enabled).map(move |s| {
                        serde_json::json!({
                            "name": s.name,
                            "source": source,
                            "enabled": true,
                        })
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

pub async fn api_skills_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

async fn api_search_handler(
    repos: Vec<serde_json::Value>,
    source: &str,
    query: &str,
) -> Json<serde_json::Value> {
    ...
}

pub async fn api_skills_search_handler(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ...
}

// ── Images ───────────────────────────────────────────────────────────────────

pub async fn api_cached_images_handler() -> impl IntoResponse {
    ...
}

pub async fn api_delete_cached_image_handler(Path(tag): Path<String>) -> impl IntoResponse {
    ...
}

pub async fn api_prune_cached_images_handler() -> impl IntoResponse {
    ...
}

pub async fn api_check_packages_handler(Json(body): Json<serde_json::Value>) -> impl IntoResponse {
    ...
}

pub async fn api_get_default_image_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

pub async fn api_set_default_image_handler(
    State(state): State<AppState>,
    Json(body): Json<serde_json::Value>,
) -> impl IntoResponse {
    ...
}

pub async fn api_get_shared_home_handler() -> impl IntoResponse {
    ...
}

pub async fn api_set_shared_home_handler(
    Json(body): Json<SandboxSharedHomeUpdateRequest>,
) -> impl IntoResponse {
    ...
}

pub async fn api_build_image_handler(Json(body): Json<serde_json::Value>) -> impl IntoResponse {
    ...
}

// ── Containers ───────────────────────────────────────────────────────────────

pub async fn api_list_containers_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

pub async fn api_stop_container_handler(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> impl IntoResponse {
    ...
}

pub async fn api_remove_container_handler(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> impl IntoResponse {
    ...
}

pub async fn api_clean_all_containers_handler(State(state): State<AppState>) -> impl IntoResponse {
    ...
}

pub async fn api_disk_usage_handler() -> impl IntoResponse {
    ...
}

pub async fn api_restart_daemon_handler() -> impl IntoResponse {
    ...
}
