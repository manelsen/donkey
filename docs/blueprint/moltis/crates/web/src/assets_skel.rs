//! Static asset serving with three-tier resolution:
//!
//! 1. **Dev filesystem** — `MOLTIS_ASSETS_DIR` env var or auto-detected from
//!    the crate source tree when running via `cargo run`.
//! 2. **External share dir** — `share_dir()/web/` for packaged deployments
//!    (Debian, RPM, Docker) where assets live outside the binary.
//! 3. **Embedded fallback** — `include_dir!` compiled into the binary (only
//!    available when the `embedded-assets` feature is enabled).

use std::{
    path::{Component, Path as FsPath, PathBuf},
    sync::LazyLock,
};

use {
    axum::{extract::Path, http::StatusCode, response::IntoResponse},
    tracing::info,
};

// ── Embedded assets (feature-gated) ─────────────────────────────────────────

#[cfg(feature = "embedded-assets")]
static ASSETS: include_dir::Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets");

// Fail compilation with a clear message if style.css hasn't been generated.
// Run `just build-css` (or `cd crates/web/ui && ./build.sh`) to generate it.
#[cfg(feature = "embedded-assets")]
const _: &str = include_str!("assets/style.css");

// ── Asset source resolution ─────────────────────────────────────────────────

/// Resolved asset source, checked once at startup.
enum AssetSource {
    ...
}

static ASSET_SOURCE: LazyLock<AssetSource> = LazyLock::new(|| {
    // 1. Explicit env var
    if let Ok(dir) = std::env::var("MOLTIS_ASSETS_DIR") {
        let p = PathBuf::from(dir);
        if p.is_dir() {
            info!("Serving assets from filesystem: {}", p.display());
            return AssetSource::Filesystem(p);
        }
    }

    // 2. Auto-detect cargo source tree (dev mode)
    let cargo_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src/assets");
    if cargo_dir.is_dir() {
        info!("Serving assets from filesystem: {}", cargo_dir.display());
        return AssetSource::Filesystem(cargo_dir);
    }

    // 3. External share directory
    if let Some(share) = moltis_config::share_dir() {
        let web_dir = share.join("web");
        if web_dir.is_dir() {
            info!(
                "Serving assets from external share dir: {}",
                web_dir.display()
            );
            return AssetSource::External(web_dir);
        }
    }

    // 4. Embedded fallback (or unavailable)
    #[cfg(feature = "embedded-assets")]
    {
        info!("Serving assets from embedded binary");
        AssetSource::Embedded
    }
    #[cfg(not(feature = "embedded-assets"))]
    {
        info!("No asset source available (embedded-assets feature disabled)");
        AssetSource::Unavailable
    }
});

/// Whether we're serving from the filesystem (dev mode) or embedded/external (release).
pub(crate) fn is_dev_assets() -> bool {
    ...
}

/// Compute a short content hash of all assets for cache-busting versioned URLs.
pub(crate) fn asset_content_hash() -> String {
    ...
}

/// Walk a filesystem directory for hashing, storing (relative_path, file_bytes)
/// pairs sorted by path.
fn walk_dir_for_hash(
    base: &FsPath,
    dir: &FsPath,
    out: &mut std::collections::BTreeMap<String, Vec<u8>>,
) {
    ...
}

fn mime_for_path(path: &str) -> &'static str {
    ...
}

/// Read a file from a filesystem directory with path-traversal protection.
fn read_from_dir(dir: &std::path::Path, path: &str) -> Option<Vec<u8>> {
    ...
}

/// Read an asset file using three-tier resolution.
fn read_asset(path: &str) -> Option<Vec<u8>> {
    ...
}

/// Read raw asset bytes by path. Used by `share_render.rs` for the favicon.
pub fn read_asset_bytes(path: &str) -> Option<Vec<u8>> {
    ...
}

/// Versioned assets: `/assets/v/<hash>/path` — immutable, cached forever.
pub async fn versioned_asset_handler(
    Path((_version, path)): Path<(String, String)>,
) -> impl IntoResponse {
    ...
}

/// Unversioned assets: `/assets/path` — always revalidate.
pub async fn asset_handler(Path(path): Path<String>) -> impl IntoResponse {
    ...
}

/// PWA manifest: `/manifest.json` — served from assets root.
pub async fn manifest_handler() -> impl IntoResponse {
    ...
}

/// Service worker: `/sw.js` — served from assets root, no-cache for updates.
pub async fn service_worker_handler() -> impl IntoResponse {
    ...
}

fn serve_asset(path: &str, cache_control: &'static str) -> axum::response::Response {
    ...
}
