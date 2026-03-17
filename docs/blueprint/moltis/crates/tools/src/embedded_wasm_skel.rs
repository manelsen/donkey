//! WASM component loading with three-tier resolution:
//!
//! 1. **Debug filesystem** — reads from `target/wasm32-wasip2/release/` for
//!    iterative development without relinking the host.
//! 2. **External share dir** — `share_dir()/wasm/` for packaged deployments
//!    where WASM components live outside the binary.
//! 3. **Embedded fallback** — `include_bytes!` compiled into the binary (only
//!    when both `wasm` and `embedded-wasm` features are enabled).

#[cfg(feature = "wasm")]
use std::borrow::Cow;
#[cfg(all(feature = "wasm", debug_assertions))]
use std::path::PathBuf;

#[cfg(feature = "wasm")]
use crate::Result;

// ── Embedded constants (release + embedded-wasm) ────────────────────────────

#[cfg(all(feature = "wasm", feature = "embedded-wasm", not(debug_assertions)))]
const CALC_COMPONENT_RELEASE_BYTES: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../target/wasm32-wasip2/release/moltis_wasm_calc.wasm"
));
#[cfg(all(feature = "wasm", feature = "embedded-wasm", not(debug_assertions)))]
const WEB_FETCH_COMPONENT_RELEASE_BYTES: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../target/wasm32-wasip2/release/moltis_wasm_web_fetch.wasm"
));
#[cfg(all(feature = "wasm", feature = "embedded-wasm", not(debug_assertions)))]
const WEB_SEARCH_COMPONENT_RELEASE_BYTES: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../target/wasm32-wasip2/release/moltis_wasm_web_search.wasm"
));

// ── Debug path helper ───────────────────────────────────────────────────────
#[cfg(all(feature = "wasm", debug_assertions))]
fn component_debug_path(file_name: &str) -> PathBuf {
    ...
}

// ── Shared resolution logic ─────────────────────────────────────────────────

/// Try to load a WASM component from the external share directory.
#[cfg(feature = "wasm")]
fn load_from_share_dir(file_name: &str) -> Option<Cow<'static, [u8]>> {
    ...
}

/// Load a WASM component with three-tier resolution:
/// 1. Debug filesystem (debug builds only)
/// 2. External share dir
/// 3. Embedded fallback
#[cfg(all(feature = "wasm", debug_assertions))]
fn load_component(file_name: &str, tool_name: &str) -> Result<Cow<'static, [u8]>> {
    ...
}

/// Load the embedded calc component bytes.
///
/// In debug builds this reads the guest artifact from `target/` so iterative
/// development can rebuild the component without relinking the host.
/// In release builds the resolution order is: external share dir → embedded.
#[cfg(feature = "wasm")]
pub fn calc_component_bytes() -> Result<Cow<'static, [u8]>> {
    ...
}

/// Load the embedded web_fetch component bytes.
///
/// In release builds the resolution order is: external share dir → embedded.
#[cfg(feature = "wasm")]
pub fn web_fetch_component_bytes() -> Result<Cow<'static, [u8]>> {
    ...
}

/// Load the embedded web_search component bytes.
///
/// In release builds the resolution order is: external share dir → embedded.
#[cfg(feature = "wasm")]
pub fn web_search_component_bytes() -> Result<Cow<'static, [u8]>> {
    ...
}

/// Whether the release bytes are pre-compiled (`.cwasm`) or raw (`.wasm`).
///
/// Used by `register_wasm_tools()` to choose between `deserialize_component()`
/// and `compile_component()`.
#[cfg(feature = "wasm")]
pub fn is_precompiled() -> bool {
    ...
}
