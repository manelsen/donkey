//! SPA templates, gon data, and template rendering.

use std::collections::HashSet;

use {
    askama::Template,
    axum::response::{Html, IntoResponse},
    moltis_gateway::state::GatewayState,
    tracing::warn,
};

use crate::assets::{asset_content_hash, is_dev_assets};

// ── SPA routes ───────────────────────────────────────────────────────────────

#[derive(serde::Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SpaRoutes {
    ...
}

pub(crate) static SPA_ROUTES: SpaRoutes = SpaRoutes {
    chats: "/chats",
    settings: "/settings",
    providers: "/settings/providers",
    security: "/settings/security",
    identity: "/settings/identity",
    config: "/settings/config",
    logs: "/settings/logs",
    nodes: "/settings/nodes",
    onboarding: "/onboarding",
    projects: "/projects",
    skills: "/skills",
    crons: "/settings/crons",
    monitoring: "/monitoring",
    graphql: "/settings/graphql",
};

// ── GonData ──────────────────────────────────────────────────────────────────

/// Server-side data injected into every page as `window.__MOLTIS__`
/// (gon pattern — see CLAUDE.md § Server-Injected Data).
#[derive(serde::Serialize)]
pub(crate) struct GonData {
    ...
}

#[derive(serde::Serialize)]
struct SandboxGonInfo {
    ...
}

/// Memory snapshot included in gon data and tick broadcasts.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MemSnapshot {
    ...
}

/// Collect a point-in-time memory snapshot (process RSS + local llama.cpp +
/// system memory).
pub(crate) fn collect_mem_snapshot() -> MemSnapshot {
    ...
}

// ── Git branch ───────────────────────────────────────────────────────────────

fn detect_git_branch() -> Option<String> {
    ...
}

fn parse_git_branch(raw: &str) -> Option<String> {
    ...
}

const SESSION_PREVIEW_MAX_CHARS: usize = 200;

fn truncate_preview(text: &str, max_chars: usize) -> String {
    ...
}

async fn build_recent_sessions_snapshot(gw: &GatewayState, limit: usize) -> Vec<serde_json::Value> {
    ...
}

// ── NavCounts ────────────────────────────────────────────────────────────────

#[derive(Debug, Default, serde::Serialize)]
pub(crate) struct NavCounts {
    ...
}

pub(crate) async fn build_nav_counts(gw: &GatewayState) -> NavCounts {
    ...
}

// ── GonData builder ──────────────────────────────────────────────────────────

pub(crate) async fn build_gon_data(gw: &GatewayState) -> GonData {
    ...
}

// ── Templates ────────────────────────────────────────────────────────────────

/// Unix epoch (milliseconds) captured once at process startup.
pub(crate) static PROCESS_STARTED_AT_MS: std::sync::LazyLock<u64> =
    std::sync::LazyLock::new(|| {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64
    });

pub(crate) const SHARE_IMAGE_URL: &str = "https://www.moltis.org/og-social.jpg?v=4";

/// Default Shiki CDN URL when `server.shiki_cdn_url` is unset.
///
/// Use the bundled esm.sh entrypoint to ensure submodule imports resolve
/// correctly outside esm.sh origin.
const DEFAULT_SHIKI_CDN_URL: &str = "https://esm.sh/shiki@3.2.1?bundle";

#[derive(Clone, Copy)]
pub(crate) enum SpaTemplate {
    ...
}

pub(crate) struct ShareMeta {
    ...
}

#[derive(Template)]
#[template(path = "index.html", escape = "html")]
struct IndexHtmlTemplate<'a> {
    ...
}

#[derive(Template)]
#[template(path = "login.html", escape = "html")]
struct LoginHtmlTemplate<'a> {
    ...
}

#[derive(Template)]
#[template(path = "onboarding.html", escape = "html")]
struct OnboardingHtmlTemplate<'a> {
    ...
}

#[derive(Template)]
#[template(path = "setup-required.html", escape = "html")]
struct SetupRequiredHtmlTemplate<'a> {
    ...
}

#[derive(serde::Deserialize)]
pub struct ShareAccessQuery {
    ...
}

pub(crate) fn script_safe_json<T: serde::Serialize>(value: &T) -> String {
    let json = match serde_json::to_string(value) {
        Ok(json) => json,
        Err(e) => {
            warn!(error = %e, "failed to serialize gon data for html template");
            "{}".to_owned()
        },
    };
    json.replace('<', "\\u003c")
        .replace('>', "\\u003e")
        .replace('&', "\\u0026")
        .replace('\u{2028}', "\\u2028")
        .replace('\u{2029}', "\\u2029")
}

pub(crate) fn build_share_meta(identity: &moltis_config::ResolvedIdentity) -> ShareMeta {
    ...
}

pub(crate) fn identity_name(identity: &moltis_config::ResolvedIdentity) -> &str {
    ...
}

pub(crate) async fn render_spa_template(
    gateway: &GatewayState,
    template: SpaTemplate,
) -> axum::response::Response {
    ...
}

// ── Onboarding helpers ───────────────────────────────────────────────────────

pub(crate) fn should_redirect_to_onboarding(path: &str, onboarded: bool) -> bool {
    ...
}

pub(crate) fn should_redirect_from_onboarding(onboarded: bool, auth_setup_pending: bool) -> bool {
    ...
}

fn is_onboarding_path(path: &str) -> bool {
    ...
}

pub(crate) async fn onboarding_completed(gw: &GatewayState) -> bool {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[test]
    fn script_safe_json_escapes_html() {
    ...
}

    #[test]
    fn setup_required_template_renders_html() {
    ...
}

    #[test]
    fn mem_snapshot_omits_llama_cpp_when_none() {
    ...
}

    #[test]
    fn mem_snapshot_includes_llama_cpp_when_present() {
    ...
}

    #[test]
    fn onboarding_redirect_waits_for_auth_recovery() {
    ...
}
}
