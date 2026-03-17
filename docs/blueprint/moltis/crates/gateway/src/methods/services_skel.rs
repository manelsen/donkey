use std::{
    collections::HashMap,
    path::{Component, Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use tracing::warn;

use {
    moltis_config::VoiceSttProvider,
    moltis_protocol::{ErrorShape, error_codes},
};

use crate::broadcast::{BroadcastOpts, broadcast};

use super::{MethodContext, MethodRegistry};

pub(super) fn model_probe_params(provider: Option<&str>) -> serde_json::Value {
    ...
}

async fn active_session_key_for_ctx(ctx: &MethodContext) -> Option<String> {
    ...
}

async fn default_agent_id_for_ctx(ctx: &MethodContext) -> String {
    ...
}

async fn agent_exists_for_ctx(ctx: &MethodContext, agent_id: &str) -> bool {
    ...
}

async fn resolve_session_agent_id_for_ctx(ctx: &MethodContext) -> String {
    ...
}

fn parse_agent_id_param(params: &serde_json::Value) -> Option<String> {
    ...
}

async fn resolve_requested_agent_id(
    ctx: &MethodContext,
    params: &serde_json::Value,
) -> Result<String, ErrorShape> {
    ...
}

fn read_identity_payload_for_agent(agent_id: &str) -> serde_json::Value {
    ...
}

fn write_soul_for_agent(agent_id: &str, soul: Option<String>) -> Result<(), ErrorShape> {
    ...
}

fn normalize_relative_agent_path(path: &str) -> Result<PathBuf, ErrorShape> {
    ...
}

fn read_agent_file(agent_id: &str, relative_path: &Path) -> Result<String, ErrorShape> {
    ...
}

fn list_agent_workspace_files_recursively(
    root: &Path,
    base: &Path,
    files: &mut Vec<serde_json::Value>,
) {
    ...
}

pub(super) fn register(reg: &mut MethodRegistry) {
    ...
}

async fn reload_hooks(state: &Arc<crate::state::GatewayState>) {
    ...
}

/// Persist the disabled hooks set to `data_dir/disabled_hooks.json`.
async fn persist_disabled_hooks(state: &Arc<crate::state::GatewayState>) {
    ...
}
