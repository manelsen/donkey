//! Web UI: static asset serving, SPA routing, share pages, terminal PTY,
//! and all browser-facing handlers.
//!
//! This crate depends on `moltis-gateway` for [`AppState`] and server-side
//! services. It provides [`web_routes()`] which returns an Axum `Router` that
//! the CLI (or any other host) can merge into the gateway router.

pub mod api;
pub mod assets;
pub mod error;
pub mod gon;
pub mod oauth;
pub mod share;
pub mod share_render;
pub mod spa;
pub mod templates;
pub mod terminal;

pub use error::{Error, Result};

use {
    axum::{Router, routing::get},
    moltis_gateway::server::AppState,
};

/// Build the web-UI router: pages, API routes, assets, and SPA fallback.
///
/// Does **not** include the `auth_gate` middleware — the caller applies it
/// globally after merging with the gateway base router (matching the old
/// architecture where auth_gate ran on every inbound request).
pub fn web_routes() -> Router<AppState> {
    ...
}

/// API routes served behind auth.
fn build_api_routes() -> Router<AppState> {
    ...
}

/// Add feature-specific routes to API routes.
fn add_feature_routes(routes: Router<AppState>) -> Router<AppState> {
    ...
}
