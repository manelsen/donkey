//! Share page rendering: template structs and helper functions for generating
//! the static HTML share page and the OG social-image SVG.

use {
    askama::Template,
    base64::Engine as _,
    chrono::{Local, TimeZone, Utc},
};

use moltis_gateway::share_store::{ShareSnapshot, ShareVisibility, SharedMessageRole};

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

/// Render a complete share HTML page (the same output the Askama template
/// produces) without requiring a per-request nonce.
///
/// `share_image_url` is the absolute or origin-relative URL to the OG image
/// SVG for this share (e.g. `/share/{id}/og-image.svg`).
pub fn render_share_html(
    snapshot: &ShareSnapshot,
    identity: &moltis_config::ResolvedIdentity,
    share_id: &str,
    visibility: ShareVisibility,
    view_count: u64,
    share_image_url: &str,
) -> crate::Result<String> {
    ...
}

/// Render the OG social-image SVG for a share.
pub fn render_share_og_svg(
    snapshot: &ShareSnapshot,
    identity: &moltis_config::ResolvedIdentity,
) -> String {
    ...
}

// ---------------------------------------------------------------------------
// Askama template structs
// ---------------------------------------------------------------------------

#[derive(Template)]
#[template(path = "share.html", escape = "html")]
pub(crate) struct ShareHtmlTemplate<'a> {
    ...
}

pub(crate) struct ShareMessageView {
    ...
}

pub(crate) struct ShareMeta {
    ...
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

pub(crate) fn identity_name(identity: &moltis_config::ResolvedIdentity) -> &str {
    ...
}

pub(crate) fn truncate_for_meta(text: &str, max: usize) -> String {
    ...
}

fn first_share_message_preview(snapshot: &ShareSnapshot) -> String {
    ...
}

pub(crate) fn build_session_share_meta(
    identity: &moltis_config::ResolvedIdentity,
    snapshot: &ShareSnapshot,
) -> ShareMeta {
    ...
}

pub(crate) fn human_share_time(ts_ms: u64) -> String {
    ...
}

fn share_user_label(identity: &moltis_config::ResolvedIdentity) -> String {
    ...
}

fn share_assistant_label(identity: &moltis_config::ResolvedIdentity) -> String {
    ...
}

fn image_dimensions_from_data_url(data_url: &str) -> Option<(u32, u32)> {
    ...
}

pub(crate) fn map_share_message_views(
    snapshot: &ShareSnapshot,
    identity: &moltis_config::ResolvedIdentity,
) -> Vec<ShareMessageView> {
    ...
}

// ---------------------------------------------------------------------------
// Social-image SVG rendering
// ---------------------------------------------------------------------------

static SHARE_SOCIAL_BRAND_ICON_DATA_URL: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| {
        let png_bytes = crate::assets::read_asset_bytes("icons/favicon-compact-512.png")
            .unwrap_or_else(|| {
                #[cfg(feature = "embedded-assets")]
                {
                    include_bytes!("assets/icons/favicon-compact-512.png").to_vec()
                }
                #[cfg(not(feature = "embedded-assets"))]
                {
                    Vec::new()
                }
            });
        let encoded = base64::engine::general_purpose::STANDARD.encode(&png_bytes);
        format!("data:image/png;base64,{encoded}")
    });

fn escape_svg_text(text: &str) -> String {
    ...
}

fn normalize_share_social_text(text: &str) -> String {
    ...
}

fn wrap_share_social_line(text: &str, max_chars: usize) -> Vec<String> {
    ...
}

fn build_share_social_text_lines(
    snapshot: &ShareSnapshot,
    identity: &moltis_config::ResolvedIdentity,
    max_chars: usize,
    max_lines: usize,
) -> Vec<String> {
    ...
}

fn build_share_social_image_svg(
    snapshot: &ShareSnapshot,
    identity: &moltis_config::ResolvedIdentity,
) -> String {
    ...
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {

    fn default_identity() -> moltis_config::ResolvedIdentity {
    ...
}

    fn shared_msg(role: SharedMessageRole, content: &str) -> SharedMessage {
    ...
}

    fn minimal_snapshot() -> ShareSnapshot {
    ...
}

    #[test]
    fn render_share_html_produces_valid_output() -> crate::Result<()> {
    ...
}

    #[test]
    fn render_share_og_svg_produces_svg() {
    ...
}

    #[test]
    fn share_template_renders_theme_toggle_and_audio() {
    ...
}

    #[test]
    fn map_share_message_views_skips_system_and_notice() {
    ...
}

    #[test]
    fn share_labels_use_identity_user_and_emoji() {
    ...
}

    #[test]
    fn share_labels_fallback_when_identity_fields_missing() {
    ...
}

    #[test]
    fn share_social_image_svg_uses_session_content_and_escapes() {
    ...
}

    #[test]
    fn map_share_message_views_includes_tool_result_media_and_links() {
    ...
}

    #[test]
    fn map_share_message_views_marks_exec_tool_cards() {
    ...
}
}
