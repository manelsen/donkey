#[cfg(feature = "wasm")]
use std::{
    collections::HashMap,
    sync::{RwLock, RwLockReadGuard, RwLockWriteGuard},
};

#[cfg(feature = "wasm")]
use anyhow::Result;
#[cfg(feature = "wasm")]
use sha2::{Digest, Sha256};
#[cfg(feature = "wasm")]
use wasmtime_wasi::WasiView;

#[cfg(feature = "wasm")]
use crate::wasm_component::{HttpHostImpl, add_http_outgoing_handler_to_linker};

#[cfg(feature = "wasm")]
type ComponentCache = HashMap<[u8; 32], wasmtime::component::Component>;

/// Shared Wasmtime engine for component-model and core module compilation.
///
/// Components are cached in-memory by SHA-256 of the original bytes.
#[cfg(feature = "wasm")]
pub struct WasmComponentEngine {
    ...
}

#[cfg(feature = "wasm")]
impl WasmComponentEngine {
    pub fn new(memory_reservation: Option<u64>) -> Result<Self> {

    #[must_use]
    pub fn engine(&self) -> &wasmtime::Engine {
    ...
}

    pub fn compile_component(&self, wasm_bytes: &[u8]) -> Result<wasmtime::component::Component> {
    ...
}

    /// Deserialize a pre-compiled component (AOT `.cwasm`).
    ///
    /// # Safety
    /// The `precompiled` bytes **must** come from a trusted source — typically
    /// `include_bytes!` of a `.cwasm` produced by `Engine::precompile_component`
    /// with the **same** `wasmtime::Config`.
    ///
    /// # Errors
    /// Returns an error if deserialization fails (e.g. config mismatch).
    #[allow(unsafe_code)]
    pub unsafe fn deserialize_component(
        &self,
        precompiled: &[u8],
    ) -> Result<wasmtime::component::Component> {
    ...
}

    pub fn compile_module(&self, wasm_bytes: &[u8]) -> Result<wasmtime::Module> {
    ...
}

    pub fn create_http_linker<T>(
        &self,
        host_getter: fn(&mut T) -> &mut HttpHostImpl,
    ) -> Result<wasmtime::component::Linker<T>>
    where
        T: WasiView + 'static,
    {
        let mut linker = wasmtime::component::Linker::new(&self.engine);
        wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;
        add_http_outgoing_handler_to_linker(&mut linker, host_getter)?;
        Ok(linker)
    }

    fn read_cache(&self) -> RwLockReadGuard<'_, ComponentCache> {
    ...
}

    fn write_cache(&self) -> RwLockWriteGuard<'_, ComponentCache> {
    ...
}

    #[cfg(test)]
    fn component_cache_len(&self) -> usize {
    ...
}
}

#[cfg(feature = "wasm")]
pub fn hash_component_bytes(wasm_bytes: &[u8]) -> [u8; 32] {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(all(test, feature = "wasm"))]
mod tests {

    fn component_b() -> &'static [u8] {
    ...
}

    fn module_a() -> &'static [u8] {
    ...
}

    #[test]
    fn compile_component_round_trip_and_cache_hit() {
    ...
}

    #[test]
    fn compile_component_different_bytes_different_entries() {
    ...
}

    #[test]
    fn compile_module_core_wasm() {
    ...
}

    #[test]
    fn compile_component_concurrent_access() {
    ...
}
}
