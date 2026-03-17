use std::path::PathBuf;

use anyhow::{Context, Result};

/// Pre-compile WASM components to `.cwasm` for AOT deserialization at runtime.
///
/// Uses the same `wasmtime::Config` as `WasmComponentEngine::new()` in
/// `crates/tools/src/wasm_engine.rs` so the serialized bytes are compatible.
fn main() -> Result<()> {
    ...
}
